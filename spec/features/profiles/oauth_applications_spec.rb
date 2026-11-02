# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Profile > Applications', feature_category: :user_profile do
  include Spec::Support::Helpers::ModalHelpers

  let(:user) { create(:user) }
  let(:application) { create(:oauth_application, owner: user) }

  before do
    sign_in(user)
  end

  describe 'User manages applications', :js do
    context 'when viewing an application' do
      it 'includes application name' do
        visit oauth_application_path(application)

        expect(page).to have_content("Application: #{application.name}")

        within_testid 'breadcrumb-links' do
          expect(find('li:last-of-type')).to have_link(application.name)
        end
      end

      it "has 'Device authorization grant' disabled" do
        visit oauth_application_path(application)

        expect(find_by_testid('device-code-enabled-value')).to have_content('No')
      end
    end

    context 'when updating an application' do
      it "supports enabling 'Device authorization grant'" do
        visit edit_oauth_application_path(application)

        expect(find_by_testid('device-code-enabled-checkbox')).not_to be_checked

        find_by_testid('device-code-enabled-checkbox').click

        click_button 'Save application'

        expect(find_by_testid('device-code-enabled-value')).to have_content('Yes')
      end
    end

    it 'deletes an application' do
      create(:oauth_application, owner: user)
      visit oauth_applications_path

      within_testid('oauth-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('1')
        end
        click_button 'Destroy'
      end

      accept_gl_confirm(button_text: 'Destroy')

      expect(page).to have_content('The application was deleted successfully')
      within_testid('oauth-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('0')
        end
      end
      within_testid('oauth-authorized-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('0')
        end
      end
    end
  end

  describe 'Authorized applications', :js do
    let(:other_user) { create(:user) }
    let(:application) { create(:oauth_application, owner: user) }
    let(:created_at) { 2.days.ago }
    let(:token) { create(:oauth_access_token, application: application, resource_owner: user) }
    let(:anonymous_token) { create(:oauth_access_token, resource_owner: user) }

    before do
      stub_feature_flags(iam_svc_oauth: false)
    end

    context 'with multiple access token types and multiple owners' do
      let!(:token2) { create(:oauth_access_token, application: application, resource_owner: user) }
      let!(:other_user_token) { create(:oauth_access_token, application: application, resource_owner: other_user) }

      before do
        token.update_column(:created_at, created_at)
        token2.update_column(:created_at, created_at - 1.day)
        anonymous_token.update_columns(application_id: nil, created_at: 1.day.ago)
      end

      it 'displays the correct authorized applications' do
        visit oauth_applications_path

        within_testid('oauth-authorized-applications') do
          within_testid('crud-count') do
            expect(page).to have_content('2')
          end
        end

        within_testid('oauth-authorized-applications') do
          # Ensure the correct user's token details are displayed
          # when the application has more than one token
          page.within("tr#application_#{application.id}") do
            expect(page).to have_content(created_at)
            expect(page).to have_content("#{user.name} added this OAuth application")
          end

          expect(page).to have_content('Anonymous')
          expect(page).not_to have_content(other_user_token.created_at)
        end
      end
    end

    it 'deletes an authorized application' do
      token
      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        page.within("tr#application_#{application.id}") do
          click_button 'Revoke'
        end
      end

      accept_gl_confirm(button_text: 'Revoke application')

      expect(page).to have_content('The application was revoked access.')
      within_testid('oauth-authorized-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('0')
        end
      end
    end

    it 'does not show owner details for an anonymous authorized application' do
      anonymous_token.update_column(:application_id, nil)
      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        expect(page).to have_content('Anonymous')
        expect(page).not_to have_content('added this OAuth application')
      end
    end

    it 'deletes an anonymous authorized application' do
      anonymous_token
      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('1')
        end
        click_button 'Revoke'
      end

      accept_gl_confirm(button_text: 'Revoke application')

      expect(page).to have_content('The application was revoked access.')
      within_testid('oauth-authorized-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('0')
        end
      end
    end
  end

  describe 'Authorized applications backed by oauth_consents' do
    let(:other_app) { create(:oauth_application) }
    let!(:consent) { create(:oauth_consent, user: user, application: other_app, granted_scopes: %w[openid profile]) }

    let(:iam_response) { ::Gitlab::Iam::Auth::V1::InternalOAuthTokensServiceRevokeUserClientTokensResponse.new }

    before do
      stub_feature_flags(iam_svc_oauth: user)

      allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
        allow(client).to receive(:revoke_user_client_tokens).and_return(iam_response)
      end
    end

    it 'displays consents with a locally-resolvable application' do
      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        within_testid('crud-count') do
          expect(page).to have_content('1')
        end

        expect(page).to have_content(other_app.name)
        expect(page).to have_content('openid profile')
        expect(page).to have_content("#{other_app.owner.name} added this OAuth application")
      end
    end

    context 'when a consent belongs to an application registered on another cell' do
      let!(:cross_cell_consent) { create(:oauth_consent, :cross_cell, user: user, granted_scopes: %w[api]) }

      let(:iam_client_response) do
        ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceGetClientResponse.new(
          client: ::Gitlab::Iam::Auth::V1::ManagedClient.new(
            client_id: cross_cell_consent.client_id,
            client_name: 'Remote app',
            owner: 'Jane Doe',
            created_at: Google::Protobuf::Timestamp.new(seconds: 2.days.ago.to_i)
          )
        )
      end

      before do
        allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
          allow(client).to receive(:get_oauth_application).and_return(iam_client_response)
        end
      end

      it 'shows the application as IAM describes it, without a Revoke button', :aggregate_failures do
        visit oauth_applications_path

        within_testid('oauth-authorized-applications') do
          within_testid('crud-count') do
            expect(page).to have_content('2')
          end

          row = find('tr', text: 'Remote app')
          expect(row).to have_content('Jane Doe added this OAuth application 2 days ago.')
          expect(row).to have_content('api')
          expect(row).not_to have_button('Revoke')
          expect(page).to have_button('Revoke', count: 1)
        end
      end

      it 'hides the consent when IAM no longer knows the application' do
        allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
          allow(client).to receive(:get_oauth_application)
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('not found', reason: :not_found))
        end

        visit oauth_applications_path

        within_testid('oauth-authorized-applications') do
          within_testid('crud-count') do
            expect(page).to have_content('1')
          end

          expect(page).not_to have_content(cross_cell_consent.client_id)
        end
      end

      it 'names the row after the client id when IAM cannot answer', :aggregate_failures do
        allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
          allow(client).to receive(:get_oauth_application)
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('unavailable', reason: :unavailable))
        end

        visit oauth_applications_path

        within_testid('oauth-authorized-applications') do
          row = find('tr', text: cross_cell_consent.client_id)
          expect(row).to have_content('Application details are temporarily unavailable.')
          expect(row).not_to have_button('Revoke')
        end
      end
    end

    it 'revokes the consent when the user revokes the application', :js do
      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        page.within("tr#application_#{other_app.id}") do
          click_button 'Revoke'
        end
      end

      accept_gl_confirm(button_text: 'Revoke application')

      expect(page).to have_content('The application was revoked access.')
      expect(consent.reload).to be_revoked
    end

    it 'keeps the consent and shows an alert when IAM does not respond', :js do
      allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
        allow(client).to receive(:revoke_user_client_tokens).and_raise(
          Authn::IamService::GrpcClient::RequestError.new('IAM service request failed: 14', reason: :unavailable)
        )
      end

      visit oauth_applications_path

      within_testid('oauth-authorized-applications') do
        page.within("tr#application_#{other_app.id}") do
          click_button 'Revoke'
        end
      end

      accept_gl_confirm(button_text: 'Revoke application')

      expect(page).to have_content('The application could not be revoked because the authentication service did ' \
        'not respond. Nothing was changed. Try again in a few minutes.')
      expect(consent.reload).to be_authorized
    end
  end
end
