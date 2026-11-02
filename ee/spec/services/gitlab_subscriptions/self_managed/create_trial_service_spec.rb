# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SelfManaged::CreateTrialService, feature_category: :acquisition do
  let_it_be_with_reload(:user) { create(:user, preferred_language: 'en') }

  let(:params) do
    {
      first_name: 'John',
      last_name: 'Doe',
      email_address: 'john@example.com',
      company_name: 'ACME Corp',
      country: 'US',
      state: 'CA',
      consent_to_marketing: '1'
    }
  end

  let(:activation_code) { 'test-activation-code-123' }

  subject(:execute) { described_class.new(params: params, user: user).execute }

  describe '#execute' do
    context 'when the email address is not a valid format' do
      where(:email) do
        [
          nil,
          '',
          'john',
          'john@',
          '@example.com',
          'john@@example.com',
          'john doe@example.com',
          '=?utf-8?q?john?=@example.com'
        ]
      end

      with_them do
        let(:params) { super().merge(email_address: email) }

        it 'returns a form_failure error without calling CustomersDot' do
          expect(Gitlab::SubscriptionPortal::Client).not_to receive(:generate_self_managed_ultimate_trial)
          expect(GitlabSubscriptions::ActivateService).not_to receive(:new)

          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:form_failure)
          expect(result.message).to eq(s_('Trial|Please enter a valid email address.'))
        end
      end
    end

    context 'when the email address has an unusual but valid format' do
      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
          .and_return({ success: true, data: { 'activation_code' => activation_code } })

        allow_next_instance_of(GitlabSubscriptions::ActivateService) do |activate_service|
          allow(activate_service).to receive(:execute).with(activation_code).and_return({ success: true })
        end
      end

      where(:email) do
        [
          'john+trial@example.com',
          'john@mail.example.co.uk',
          'john@example.technology',
          'john@my-company.example',
          'John.Doe@Example.COM'
        ]
      end

      with_them do
        let(:params) { super().merge(email_address: email) }

        it 'returns a success response' do
          expect(execute).to be_success
        end
      end
    end

    context 'when trial creation and activation succeed' do
      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                       .and_return({ success: true,
data: { 'activation_code' => activation_code } })

        allow_next_instance_of(GitlabSubscriptions::ActivateService) do |activate_service|
          allow(activate_service).to receive(:execute)
                                       .with(activation_code)
                                       .and_return({ success: true })
        end
      end

      it 'returns a success response' do
        expect(execute).to be_success
      end

      it 'calls CustomersDot with correct parameters' do
        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                        .with(hash_including(
                                                          trial: hash_including(
                                                            name: 'John Doe',
                                                            email: 'john@example.com',
                                                            language: 'en',
                                                            company: 'ACME Corp',
                                                            country: 'US',
                                                            state: 'CA',
                                                            consent_to_marketing: '1'
                                                          )
                                                        ))

        execute
      end

      it 'sends the GitLab version' do
        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
          .with(hash_including(trial: hash_including(gitlab_version: Gitlab::VERSION)))

        execute
      end

      it 'sends the instance ID' do
        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
          .with(hash_including(trial: hash_including(instance_id: Gitlab::GlobalAnonymousId.instance_id)))

        execute
      end

      it 'activates license with returned activation code' do
        expect_next_instance_of(GitlabSubscriptions::ActivateService) do |activate_service|
          expect(activate_service).to receive(:execute).with(activation_code).and_return({ success: true })
        end

        execute
      end

      it 'uses the user preferred language' do
        user.update!(preferred_language: 'fr')

        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                        .with(hash_including(trial: hash_including(language: 'fr')))

        execute
      end
    end

    context 'when CustomersDot trial creation fails' do
      context 'with email taken error' do
        before do
          allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                         .and_return({
                                                           success: false,
                                                           data: {
                                                             error_attribute_map: {
                                                               base: ['only_one_trial_per_email_and_type']
                                                             }
                                                           }
                                                         })
        end

        it 'returns an error response with form_failure reason' do
          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:form_failure)
          expect(result.message).to include('already registered')
        end

        it 'tracks the duplicate email error event' do
          expect { execute }
            .to trigger_internal_events('sm_trial_create_form_duplicate_email_error').with(user: user)
        end

        it 'does not attempt activation' do
          expect(GitlabSubscriptions::ActivateService).not_to receive(:new)

          execute
        end
      end

      context 'with generic error' do
        before do
          allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                         .and_return({
                                                           success: false,
                                                           data: { error_attribute_map: { base: ['generic_error'] } }
                                                         })
        end

        it 'returns an error response with generic_failure reason' do
          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:generic_failure)
          expect(result.message).to include('GitLab Support')
        end

        it 'does not attempt activation' do
          expect(GitlabSubscriptions::ActivateService).not_to receive(:new)

          execute
        end
      end

      context 'when data is nil' do
        before do
          allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                         .and_return({ success: false, data: nil })
        end

        it 'returns an error response with generic_failure reason' do
          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:generic_failure)
          expect(result.message).to include('GitLab Support')
        end
      end

      context 'when error_attribute_map is missing' do
        before do
          allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                         .and_return({ success: false, data: {} })
        end

        it 'returns an error response with generic_failure reason' do
          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:generic_failure)
          expect(result.message).to include('GitLab Support')
        end
      end
    end

    context 'when license activation fails' do
      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_self_managed_ultimate_trial)
                                                       .and_return({ success: true,
data: { 'activation_code' => activation_code } })

        allow_next_instance_of(GitlabSubscriptions::ActivateService) do |activate_service|
          allow(activate_service).to receive(:execute)
                                       .and_return({ success: false, errors: ['Activation code is invalid'] })
        end
      end

      it 'returns generic error' do
        result = execute

        expect(result).to be_error
        expect(result.reason).to eq(:generic_failure)
        expect(result.message).to include('GitLab Support')
      end
    end
  end
end
