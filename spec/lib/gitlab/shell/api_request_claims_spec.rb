# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Shell::ApiRequestClaims, feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax

  subject(:claims) { described_class.new(payload) }

  let(:base_payload) { { 'iss' => 'gitlab-shell', 'gl_id' => 'user-1' } }

  describe '#verify' do
    subject(:result) { claims.verify(nil) }

    context 'with a check_ip claim' do
      where(:check_ip_claim, :reason, :client_ip) do
        :absent       | nil               | nil
        nil           | nil               | nil
        '1.2.3.4'     | nil               | '1.2.3.4'
        '[::1]'       | nil               | '::1'
        '2001:db8::1' | nil               | '2001:db8::1'
        '2001:DB8::1' | nil               | '2001:db8::1'
        ''            | :invalid_check_ip | nil
        'garbage'     | :invalid_check_ip | nil
        '1.2.3.0/24'  | :invalid_check_ip | nil
        123           | :invalid_check_ip | nil
        ['1.2.3.4']   | :invalid_check_ip | nil
      end

      with_them do
        let(:payload) do
          check_ip_claim == :absent ? base_payload : base_payload.merge('check_ip' => check_ip_claim)
        end

        it 'validates the claim', :aggregate_failures do
          expect(result.error?).to eq(reason.present?)
          expect(result.reason).to eq(reason)
          expect(claims.client_ip).to eq(client_ip)
        end
      end
    end

    context 'with key claims' do
      where(:gl_key_type, :gl_key_id, :reason) do
        'deploy_key' | nil   | :invalid_gl_key_id
        'deploy_key' | '5'   | :invalid_gl_key_id
        'deploy_key' | 0     | :invalid_gl_key_id
        'deploy_key' | -1    | :invalid_gl_key_id
        'key'        | 5     | nil
        'key'        | 'bad' | nil
        'ldap_key'   | 5     | nil
        'unknown'    | 5     | nil
        nil          | 5     | nil
        nil          | nil   | nil
      end

      with_them do
        let(:payload) { base_payload.merge('gl_key_type' => gl_key_type, 'gl_key_id' => gl_key_id).compact }

        it 'validates the claims without a deploy key', :aggregate_failures do
          expect(result.success?).to eq(reason.nil?)
          expect(result.reason).to eq(reason)
          expect(result.payload).not_to have_key(:deploy_key)
        end
      end
    end

    context 'with a deploy key claim' do
      subject(:result) { claims.verify(user) }

      let_it_be(:user) { create(:user) }
      let_it_be(:deploy_key) { create(:deploy_key, user: user) }

      let(:gl_key_id) { deploy_key.id }
      let(:payload) { base_payload.merge('gl_key_type' => 'deploy_key', 'gl_key_id' => gl_key_id) }

      it 'returns the deploy key for its owner', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:deploy_key]).to eq(deploy_key)
      end

      context 'when the deploy key does not exist' do
        let(:gl_key_id) { non_existing_record_id }

        it 'rejects the claim with the key id', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:deploy_key_not_found)
          expect(result.payload[:gl_key_id]).to eq(gl_key_id)
        end
      end

      context 'when the user does not own the deploy key' do
        subject(:result) { claims.verify(other_user) }

        let_it_be(:other_user) { create(:user) }

        it 'rejects the claim', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:deploy_key_user_mismatch)
        end
      end
    end
  end
end
