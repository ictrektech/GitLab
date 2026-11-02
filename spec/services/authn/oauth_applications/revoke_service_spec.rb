# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Authn::OauthApplications::RevokeService, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:application) { create(:oauth_application) }
  let_it_be_with_reload(:grant) do
    create(:oauth_access_grant, resource_owner_id: user.id, application: application,
      organization: application.organization)
  end

  let_it_be_with_reload(:access_token) { create(:oauth_access_token, resource_owner: user, application: application) }

  let(:grpc_client) { instance_double(Authn::IamService::GrpcClient) }
  let(:iam_response) { ::Gitlab::Iam::Auth::V1::InternalOAuthTokensServiceRevokeUserClientTokensResponse.new }
  # Ahead of every let_it_be consent; travel_to drops sub-second digits, so it round-trips through the DB unchanged.
  let(:cut_off) { 1.minute.from_now.change(usec: 0) }

  subject(:service) do
    described_class.new(current_user: user, application_id: application.id.to_s, client: grpc_client)
  end

  before do
    travel_to(cut_off)
    allow(grpc_client).to receive(:revoke_user_client_tokens).and_return(iam_response)
  end

  describe '#execute' do
    it 'revokes both access grants and tokens', :aggregate_failures do
      expect(grant).not_to be_revoked
      expect(access_token).not_to be_revoked

      service.execute

      expect(grant.reload).to be_revoked
      expect(access_token.reload).to be_revoked
    end

    it 'returns a success ServiceResponse' do
      response = service.execute

      expect(response).to be_success
    end

    it 'logs the revocation with the consent cut-off' do
      expect(Gitlab::AppLogger).to receive(:info).with({
        Labkit::Fields::CLASS_NAME => described_class.name,
        'message' => "OAuth application authorization revoked",
        'revoked_by' => user.username,
        'revoked_for' => user.username,
        'application_id' => application.id.to_s,
        'consents_revoked_before' => cut_off.iso8601(6)
      })

      service.execute
    end

    context 'with an active consent grant' do
      let_it_be_with_reload(:consent_grant) { create(:oauth_consent_grant, user: user, application: application) }

      it 'revokes the granular consent grant of the current user' do
        expect_next_instance_of(Authz::OauthConsentGrants::RevokeService,
          user: user, application_id: application.id.to_s) do |grant_service|
          expect(grant_service).to receive(:execute)
        end

        service.execute
      end

      it 'revokes the granular consent grant when the granular_oauth_tokens flag is disabled' do
        stub_feature_flags(granular_oauth_tokens: false)

        expect_next_instance_of(Authz::OauthConsentGrants::RevokeService) do |grant_service|
          expect(grant_service).to receive(:execute)
        end

        service.execute
      end

      it 'rolls back token and grant revocation when the consent grant revocation fails', :aggregate_failures do
        allow_next_instance_of(Authz::OauthConsentGrants::RevokeService) do |grant_service|
          allow(grant_service).to receive(:execute).and_raise(StandardError, 'boom')
        end

        expect { service.execute }.to raise_error(StandardError, 'boom')

        expect(access_token.reload).not_to be_revoked
        expect(grant.reload).not_to be_revoked
        expect(consent_grant.reload).to be_authorized
      end
    end

    context 'when iam_svc_oauth is enabled' do
      let_it_be_with_reload(:consent) { create(:oauth_consent, user: user, application: application) }
      let_it_be_with_reload(:other_user_consent) { create(:oauth_consent, application: application) }

      before do
        stub_feature_flags(iam_svc_oauth: user)
      end

      it 'revokes the IAM tokens the application holds for the user' do
        service.execute

        expect(grpc_client).to have_received(:revoke_user_client_tokens)
          .with(subject: user.id.to_s, client_id: application.uid)
      end

      it 'revokes oauth_consents for the application and current user, stamped at the write time',
        :aggregate_failures do
        service.execute

        expect(consent.reload).to be_revoked
        expect(consent.updated_at).to eq(Time.current)
        expect(other_user_consent.reload).to be_authorized
      end

      it 'reads the cut-off before the IAM call, so a consent created during the call stays authorized',
        :aggregate_failures do
        consent_during_call = nil
        allow(grpc_client).to receive(:revoke_user_client_tokens) do
          travel(1.second)
          consent_during_call = create(:oauth_consent, user: user, application: application)
          travel(1.second)
          iam_response
        end

        service.execute

        expect(consent.reload).to be_revoked
        expect(consent.updated_at).to eq(cut_off + 2.seconds)
        expect(consent_during_call.reload).to be_authorized
      end

      it 'leaves a consent created after the cut-off authorized' do
        later_consent = create(:oauth_consent, user: user, application: application, created_at: cut_off + 1.second)

        service.execute

        expect(later_consent.reload).to be_authorized
      end

      it 'revokes every authorized consent the user holds for the application' do
        second_consent = create(:oauth_consent, user: user, application: application, created_at: cut_off - 1.second)

        service.execute

        expect(second_consent.reload).to be_revoked
      end

      it 'is a no-op for consents and skips IAM when application is not found', :aggregate_failures do
        described_class
          .new(current_user: user, application_id: non_existing_record_id.to_s, client: grpc_client)
          .execute

        expect(consent.reload).to be_authorized
        expect(grpc_client).not_to have_received(:revoke_user_client_tokens)
      end

      it 'rolls back token and grant revocation when consent revocation fails', :aggregate_failures do
        allow(Authn::OauthConsent).to receive(:revoke_authorized_for).and_raise(StandardError, 'boom')

        expect { service.execute }.to raise_error(StandardError, 'boom')

        expect(access_token.reload).not_to be_revoked
        expect(grant.reload).not_to be_revoked
        expect(consent.reload).to be_authorized
      end

      context 'when the IAM call fails' do
        using RSpec::Parameterized::TableSyntax

        let(:service_down_message) do
          'The application could not be revoked because the authentication service did not respond. ' \
            'Nothing was changed. Try again in a few minutes.'
        end

        let(:timeout_message) do
          'The authentication service did not respond in time, so the application may not have been revoked. Try again.'
        end

        let(:conflict_message) { 'Another change to this application was in progress. Nothing was changed, try again.' }
        let(:generic_message) { 'The application could not be revoked. Nothing was changed, try again.' }

        where(:grpc_code, :reason, :message) do
          14 | :unavailable | ref(:service_down_message)
          4  | :timeout     | ref(:timeout_message)
          10 | :conflict    | ref(:conflict_message)
          13 | :unknown     | ref(:generic_message)
        end

        with_them do
          before do
            allow(grpc_client).to receive(:revoke_user_client_tokens).and_raise(
              Authn::IamService::GrpcClient::RequestError.new("IAM service request failed: #{grpc_code}",
                reason: reason)
            )
          end

          it 'returns an error naming the cause and revokes nothing', :aggregate_failures do
            response = service.execute

            expect(response).to be_error
            expect(response.reason).to eq(:iam_revocation_failed)
            expect(response.message).to eq(message)
            expect(access_token.reload).not_to be_revoked
            expect(grant.reload).not_to be_revoked
            expect(consent.reload).to be_authorized
          end

          it 'logs the failure with its reason' do
            expect(Gitlab::AuthLogger).to receive(:warn).with({
              Labkit::Fields::CLASS_NAME => described_class.name,
              'message' => 'OAuth application revocation failed at the authentication service',
              'revoked_by' => user.username,
              'application_id' => application.id.to_s,
              'failure_reason' => reason
            })

            service.execute
          end
        end
      end

      context 'when the local revocation fails after IAM revoked the tokens' do
        before do
          allow(Authn::OauthConsent).to receive(:revoke_authorized_for).and_raise(StandardError, 'boom')
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
        end

        it 'rolls back, reports the dangling state and asks the user to revoke again', :aggregate_failures do
          response = service.execute

          expect(response).to be_error
          expect(response.reason).to eq(:consent_revocation_failed)
          expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception).with(
            an_instance_of(StandardError),
            user_id: user.id, application_id: application.id.to_s, iam_tokens_revoked: true
          )
          expect(access_token.reload).not_to be_revoked
          expect(grant.reload).not_to be_revoked
          expect(consent.reload).to be_authorized
        end
      end
    end

    context 'when iam_svc_oauth is disabled' do
      let!(:consent) { create(:oauth_consent, user: user, application: application) }

      before do
        stub_feature_flags(iam_svc_oauth: false)
      end

      it 'does not call IAM or touch oauth_consents', :aggregate_failures do
        service.execute

        expect(grpc_client).not_to have_received(:revoke_user_client_tokens)
        expect(consent.reload).to be_authorized
      end

      it 'logs the revocation without a consent cut-off' do
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including('consents_revoked_before' => nil))

        service.execute
      end

      context 'when the local revocation fails' do
        before do
          allow_next_instance_of(Authz::OauthConsentGrants::RevokeService) do |grant_service|
            allow(grant_service).to receive(:execute).and_raise(StandardError, 'boom')
          end
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
        end

        it 'returns an error saying nothing changed', :aggregate_failures do
          response = service.execute

          expect(response).to be_error
          expect(response.reason).to eq(:revocation_failed)
          expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception).with(
            an_instance_of(StandardError),
            user_id: user.id, application_id: application.id.to_s, iam_tokens_revoked: false
          )
        end
      end
    end
  end
end
