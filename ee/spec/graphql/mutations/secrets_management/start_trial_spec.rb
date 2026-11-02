# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::SecretsManagement::StartTrial, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }

  subject(:mutation) { described_class.new(context: query_context, object: nil, field: nil) }

  before_all do
    root_group.add_owner(current_user)
    subgroup.add_owner(current_user)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(native_secrets_management: true)
  end

  describe '#resolve' do
    let(:success_response) do
      ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(success: true)
    end

    let(:trial_eligible_entitlement) { ::SecretsManagement::Entitlement.new(state: :trial_eligible) }
    let(:trial_entitlement) { ::SecretsManagement::Entitlement.new(state: :trial) }

    # The eligibility pre-check refreshes; the post-trial read resolves.
    def stub_entitlement(pre_check, post_trial = nil)
      allow(::SecretsManagement::Entitlement).to receive(:refresh!)
        .with(root_group, user: current_user)
        .and_return(pre_check)
      return unless post_trial

      allow(::SecretsManagement::Entitlement).to receive(:for!)
        .with(root_group, user: current_user)
        .and_return(post_trial)
    end

    def resolve(group_path: root_group.full_path)
      mutation.resolve(group_path: group_path)
    end

    context 'when CDot starts the trial successfully', :saas do
      before do
        allow(client).to receive(:start_secrets_manager_trial)
          .with(namespace_id: root_group.id).and_return(success_response)
        stub_entitlement(trial_eligible_entitlement, trial_entitlement)
        allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success)
        end
        # The provisioning ability needs an enrolled group with a live write
        # entitlement; the policy has its own specs, so the mutation spec grants it.
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(current_user, :provision_secrets_manager, root_group).and_return(true)
      end

      # The trial is the group's enrollment, so the group is provisioned in the
      # same step, as EnableAddOn does after a purchase.
      it 'provisions the group secrets manager' do
        expect_next_instance_of(
          ::SecretsManagement::GroupSecretsManagers::InitializeService, root_group, current_user
        ) do |service|
          expect(service).to receive(:execute).and_return(ServiceResponse.success)
        end

        resolve
      end

      context 'when the group is already provisioned' do
        before do
          allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'already there', reason: :already_initialized)
            )
          end
        end

        it 'returns the entitlement with no errors' do
          result = resolve

          expect(result[:errors]).to be_empty
          expect(result[:entitlement].state).to eq(:trial)
        end
      end

      context 'when provisioning fails' do
        before do
          allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'provisioning boom'))
          end
        end

        # CDot has already started the trial, so the entitlement is reported next
        # to the provisioning error rather than replaced by it.
        it 'returns the entitlement together with the provisioning error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement].state).to eq(:trial)
          expect(result[:errors]).to contain_exactly('provisioning boom')
        end
      end

      context 'when provisioning raises after the trial started' do
        before do
          allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
            allow(service).to receive(:execute).and_raise(StandardError, 'redis down')
          end
        end

        # InitializeService propagates a failed enqueue after its records commit;
        # the trial on CDot stands, so the payload must still carry the entitlement.
        it 'tracks the exception and reports it next to the entitlement', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(StandardError), gl_namespace_id: root_group.id)

          result = resolve

          expect(result[:entitlement].state).to eq(:trial)
          expect(result[:errors]).to contain_exactly(described_class::PROVISIONING_ERROR)
        end
      end

      context 'when the user may start the trial but not provision' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?)
            .with(current_user, :provision_secrets_manager, root_group).and_return(false)
        end

        it 'leaves the group unprovisioned and returns no error' do
          expect(::SecretsManagement::GroupSecretsManagers::InitializeService).not_to receive(:new)

          expect(resolve[:errors]).to be_empty
        end
      end

      it 'returns the post-trial entitlement with no errors', :aggregate_failures do
        result = resolve

        expect(result[:errors]).to be_empty
        expect(result[:entitlement]).to be_a(::Types::SecretsManagement::EntitlementType::Adapter)
        expect(result[:entitlement].state).to eq(:trial)
      end

      it 'tracks the secrets_manager_trial_started event' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_trial_started')
          .with(namespace: root_group, user: current_user, category: described_class.name)
          .and not_trigger_internal_events('secrets_manager_trial_start_failed')
      end

      it 'refreshes for the eligibility pre-check, then expires both cache layers before the post-trial read' do
        expect(::SecretsManagement::Entitlement).to receive(:refresh!)
          .with(root_group, user: current_user)
          .and_return(trial_eligible_entitlement)
          .ordered
        expect(client).to receive(:expire_secrets_manager_cache)
          .with(namespace_id: root_group.id)
          .ordered
        expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache)
          .with(root_group)
          .ordered
        expect(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(trial_entitlement)
          .ordered

        resolve
      end

      # Without the post-trial clear the slot outlives the trial start, and a
      # transport failure on the lookup above replays the pre-trial answer for up to 24h.
      it 'drops the resolver caches, including the last-known-good slot' do
        expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache)
          .with(root_group)
          .once

        resolve
      end

      context 'when the post-trial entitlement lookup raises' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(root_group, user: current_user)
            .and_raise(ActiveRecord::StatementInvalid, 'connection lost')
        end

        # CDot has already started the trial, so the mutation must still succeed.
        it 'reports the failure and returns a null entitlement with no errors', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(gl_namespace_id: root_group.id)
          )

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to be_empty
        end
      end
    end

    context 'when CDot rejects the request', :saas do
      where(:error_code, :expected_message) do
        [
          [:trial_already_active, 'A Secrets Manager trial is already active for this group.'],
          [:not_found, 'This group is not recognized by the subscription service.'],
          [:ineligible, 'This group is not eligible to start a Secrets Manager trial.']
        ]
      end

      with_them do
        before do
          stub_entitlement(trial_eligible_entitlement)
          allow(client).to receive(:start_secrets_manager_trial).and_return(
            ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(
              success: false, error_code: error_code
            )
          )
        end

        it 'returns the mapped error and a nil entitlement', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(expected_message)
        end

        it 'tracks the trial start failure with the error code as label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: error_code.to_s }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end

      context 'when ineligible with a CDot-supplied message' do
        before do
          stub_entitlement(trial_eligible_entitlement)
          allow(client).to receive(:start_secrets_manager_trial).and_return(
            ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(
              success: false, error_code: :ineligible, error_message: 'Namespace already used its trial'
            )
          )
        end

        it 'surfaces the CDot message' do
          expect(resolve[:errors]).to contain_exactly('Namespace already used its trial')
        end

        it 'tracks the trial start failure with the ineligible label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'ineligible' }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end
    end

    context 'when the subscription service is unreachable', :saas do
      before do
        stub_entitlement(trial_eligible_entitlement)
        allow(client).to receive(:start_secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
      end

      it 'expires no cache, since no trial was started' do
        expect(client).not_to receive(:expire_secrets_manager_cache)
        expect(::SecretsManagement::Entitlement::Resolver).not_to receive(:clear_cache)

        resolve
      end

      it 'tracks the trial start failure as unavailable' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_trial_start_failed')
          .with(
            namespace: root_group,
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'unavailable' }
          )
          .and not_trigger_internal_events('secrets_manager_trial_started')
      end

      it 'reports the failure to Sentry' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error),
          hash_including(gl_namespace_id: root_group.id)
        )

        resolve
      end
    end

    context 'when the group is not trial eligible', :saas do
      where(:state, :blocked_reason, :expected_reason) do
        [
          [:trial, nil, :trial_already_active],
          [:paid, nil, :ineligible],
          [:offline_paid, nil, :ineligible],
          [:blocked, :grace, :ineligible],
          [:ineligible, nil, :ineligible]
        ]
      end

      with_them do
        before do
          stub_entitlement(::SecretsManagement::Entitlement.new(state: state, blocked_reason: blocked_reason))
        end

        it 'rejects with the mapped error and never asks CDot for a trial', :aggregate_failures do
          expect(client).not_to receive(:start_secrets_manager_trial)

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::ERROR_MESSAGES.fetch(expected_reason))
        end

        # A cached CDot answer must not turn the caller away without asking CDot,
        # and the refresh must not delete the last-known-good slot to get there.
        it 'refreshes the entitlement without clearing any cache' do
          expect(::SecretsManagement::Entitlement).to receive(:refresh!)
            .with(root_group, user: current_user)
            .and_return(::SecretsManagement::Entitlement.new(state: state, blocked_reason: blocked_reason))
          expect(client).not_to receive(:expire_secrets_manager_cache)
          expect(::SecretsManagement::Entitlement::Resolver).not_to receive(:clear_cache)

          resolve
        end

        it 'tracks the trial start failure with the ineligibility reason as label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: expected_reason.to_s }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end
    end

    context 'when the eligibility pre-check cannot reach the subscription service', :saas do
      where(:error_class) do
        [
          [::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error],
          [::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error],
          # A CDot outage: `refresh!` never replays the last-known-good answer.
          [::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError]
        ]
      end

      with_them do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:refresh!)
            .with(root_group, user: current_user)
            .and_raise(error_class, 'boom')
        end

        it 'returns the unavailable error, reports to Sentry and never asks CDot for a trial', :aggregate_failures do
          expect(client).not_to receive(:start_secrets_manager_trial)
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(error_class),
            hash_including(gl_namespace_id: root_group.id)
          )

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
        end

        it 'tracks the trial start failure as unavailable' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'unavailable' }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end
    end

    # NamespaceEnrollment.enrollment_allowed? is false for a non-root group, so
    # GroupPolicy prevents :start_secrets_manager_trial at authorization.
    context 'when the group is not a top-level group', :saas do
      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve(group_path: subgroup.full_path) }
          .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the license does not include Secrets Manager', :saas do
      before do
        stub_licensed_features(native_secrets_management: false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the user is a maintainer, not an owner', :saas do
      let_it_be(:maintainer) { create(:user, maintainer_of: root_group) }

      let(:current_user) { maintainer }

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    # The trial belongs to the instance on self-managed, so a group Owner must
    # not be able to start it; SecretsManagerInstanceStartTrial is the entry point.
    context 'on a self-managed install' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end
  end
end
