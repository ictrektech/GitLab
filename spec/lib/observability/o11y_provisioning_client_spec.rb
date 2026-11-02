# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Observability::O11yProvisioningClient, feature_category: :observability do
  using RSpec::Parameterized::TableSyntax

  let(:user) { create(:user) }
  let(:group) { create(:group) }
  let(:client) { described_class.new }

  let(:provisioner_url) { 'https://provisioner.example.com/api/v1/provision_requests' }
  let(:api_key) { 'provisioner-api-key' }

  before do
    stub_application_setting(o11y_provisioner_url: provisioner_url, o11y_provisioner_api_key: api_key)
    stub_request(:post, provisioner_url)
      .to_return(status: 200, body: '{"status": "success"}')
  end

  describe '#provision_namespace' do
    subject(:provision_namespace) { client.provision_namespace(group, user) }

    context 'when API call is successful' do
      it 'returns success with settings params' do
        result = provision_namespace

        expect(result[:success]).to be true
        expect(result[:settings_params]).to include(
          o11y_service_name: group.id.to_s,
          o11y_service_user_email: "#{group.id}@gitlab-o11y.com",
          o11y_service_password: be_present
        )
      end

      it 'makes an API request to the provisioner service' do
        provision_namespace

        expect(WebMock).to have_requested(:post, provisioner_url)
          .with(
            body: hash_including(
              'o11y_provision_request' => hash_including(
                'group_id' => group.id,
                'email' => user.email,
                'user_name' => user.name,
                'group_path' => group.full_path,
                'is_user' => false
              )
            ),
            headers: {
              'Content-Type' => 'application/json',
              'User-Agent' => "GitLab/#{Gitlab::VERSION}",
              'X-API-Key' => api_key
            }
          )
      end
    end

    context 'when the namespace is a user (personal) namespace' do
      let_it_be(:namespace) { create(:user_namespace) }

      subject(:provision_namespace) { client.provision_namespace(namespace, user) }

      it 'returns success with settings params' do
        result = provision_namespace

        expect(result[:success]).to be true
        expect(result[:settings_params]).to include(
          o11y_service_name: namespace.id.to_s,
          o11y_service_user_email: "#{namespace.id}@gitlab-o11y.com",
          o11y_service_password: be_present
        )
      end

      it 'sends is_user as true' do
        provision_namespace

        expect(WebMock).to have_requested(:post, provisioner_url)
          .with(
            body: hash_including(
              'o11y_provision_request' => hash_including(
                'group_id' => namespace.id,
                'group_path' => namespace.full_path,
                'is_user' => true
              )
            )
          )
      end
    end

    context 'when the provisioner is not configured' do
      where(:url, :key) do
        nil                        | 'provisioner-api-key'
        ''                         | 'provisioner-api-key'
        'https://provisioner.test' | nil
        'https://provisioner.test' | ''
      end

      with_them do
        before do
          stub_application_setting(o11y_provisioner_url: url, o11y_provisioner_api_key: key)
        end

        it 'returns failure without calling the provisioner' do
          result = provision_namespace

          expect(result).to eq(success: false, error: 'Observability provisioner is not configured')
          expect(WebMock).not_to have_requested(:post, /.*/)
        end
      end
    end

    context 'when API call fails' do
      before do
        stub_request(:post, provisioner_url)
          .to_return(status: 500, body: '{"error": "Internal server error"}')
      end

      it 'returns failure with error message' do
        result = provision_namespace

        expect(result[:success]).to be false
        expect(result[:error]).to eq('API call failed for observability group setting')
      end
    end

    context 'when API call raises an exception' do
      before do
        allow(Gitlab::HTTP).to receive(:post).and_raise(SocketError.new('Network error'))
      end

      it 'returns failure with error message' do
        result = provision_namespace

        expect(result[:success]).to be false
        expect(result[:error]).to eq('API call failed for observability group setting')
      end
    end
  end

  describe 'security' do
    let(:sensitive_fields) do
      {
        'o11y_service_password' => /[a-f0-9]{32}/,
        'o11y_service_post_message_encryption_key' => /[a-f0-9]{64}/,
        'encryption_key' => /[a-f0-9]{32}/,
        'password' => /[a-f0-9]{32}/
      }
    end

    context 'when API call raises an exception' do
      before do
        allow(Gitlab::HTTP).to receive(:post).and_raise(SocketError.new('Network error'))
      end

      it 'does not include sensitive field names or patterns in error messages' do
        result = client.provision_namespace(group, user)

        sensitive_fields.each do |field_name, pattern|
          expect(result[:error]).not_to include(field_name)
          expect(result[:error]).not_to match(pattern)
        end
      end

      it 'logs API responses without filtering sensitive data' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(
            message: be_a(String),
            group_id: group.id
          )
        )

        client.provision_namespace(group, user)
      end
    end

    context 'when API call raises Gitlab::HTTP_V2::BlockedUrlError with sensitive data' do
      let(:sensitive_url) { 'https://user:secretpassword@blocked-domain.com/api' }
      let(:blocked_url_error) { Gitlab::HTTP_V2::BlockedUrlError.new("URL is blocked: #{sensitive_url}") }

      before do
        allow(Gitlab::HTTP).to receive(:post).and_raise(blocked_url_error)
      end

      it 'sanitizes sensitive data in the error message when logging' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(
            message: 'API request error for observability setting',
            group_id: group.id,
            error: 'URL is blocked: https://*****:*****@blocked-domain.com/api',
            error_class: 'Gitlab::HTTP_V2::BlockedUrlError'
          )
        )

        client.provision_namespace(group, user)
      end

      it 'does not include sensitive data in the returned error message' do
        result = client.provision_namespace(group, user)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('API call failed for observability group setting')
        expect(result[:error]).not_to include('secretpassword')
        expect(result[:error]).not_to include('user:')
      end
    end
  end
end
