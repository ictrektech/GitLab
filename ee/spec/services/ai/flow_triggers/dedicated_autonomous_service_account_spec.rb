# frozen_string_literal: true

require 'spec_helper'

# Demonstrates that an autonomous (scheduled) trigger and an interactive trigger
# can coexist on the same catalog flow, because the autonomous one runs as its
# own service account instead of the consumer's shared account.
RSpec.describe 'Dedicated service account for autonomous flow triggers', feature_category: :dap_triggers do
  def service_accounts_without_composite_identity
    User.where(user_type: 'service_account', composite_identity_enforced: false)
  end

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let_it_be(:shared_service_account) do
    create(:service_account, provisioned_by_group: group, composite_identity_enforced: true, developer_of: project)
  end

  let_it_be(:parent_item_consumer) do
    create(:ai_catalog_item_consumer, :parent_item_consumer, group: group, service_account: shared_service_account)
  end

  let_it_be(:item_consumer) do
    create(:ai_catalog_item_consumer, :for_flow,
      project: project, item: parent_item_consumer.item, parent_item_consumer: parent_item_consumer)
  end

  let(:mention) { Ai::FlowTrigger::EVENT_TYPES[:mention] }
  let(:scheduled) { Ai::FlowTrigger::EVENT_TYPES[:scheduled] }

  before do
    stub_feature_flags(autonomous_service_account_execution: true)
    # The factory flow has no real config; master validates custom flow definitions.
    allow_next_instance_of(::Ai::Catalog::Items::ValidateConfigService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success)
    end
    stub_ee_application_setting(duo_features_enabled: true)
    allow(Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
  end

  def create_trigger(event_types:, description:)
    Ai::FlowTriggers::CreateService
      .new(project: project, current_user: current_user)
      .execute(
        ai_catalog_item_consumer_id: item_consumer.id,
        event_types: event_types,
        description: description
      )
  end

  it 'lets an interactive and a scheduled trigger share one flow' do
    interactive = create_trigger(event_types: [mention], description: 'on mention')
    expect(interactive).to be_success

    scheduled_result = create_trigger(event_types: [scheduled], description: 'nightly')
    expect(scheduled_result).to be_success

    expect(interactive.payload.service_account).to eq(shared_service_account)
    expect(scheduled_result.payload.service_account).not_to eq(shared_service_account)
  end

  it 'keeps composite identity on the shared account and off the dedicated one' do
    create_trigger(event_types: [mention], description: 'on mention')
    scheduled_result = create_trigger(event_types: [scheduled], description: 'nightly')

    expect(shared_service_account.reload).to be_composite_identity_enforced
    expect(scheduled_result.payload.service_account).not_to be_composite_identity_enforced
  end

  it 'gives the dedicated account project access' do
    scheduled_result = create_trigger(event_types: [scheduled], description: 'nightly')

    expect(project.team.member?(scheduled_result.payload.service_account)).to be(true)
  end

  def update_trigger(trigger, params)
    Ai::FlowTriggers::UpdateService
      .new(project: project, current_user: current_user, trigger: trigger)
      .execute(params)
  end

  it 'reuses the dedicated account when the trigger is updated' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    original = trigger.service_account

    result = update_trigger(trigger,
      ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled], description: 'nightly renamed')

    expect(result).to be_success
    expect(trigger.reload.service_account).to eq(original)
  end

  describe 'keeping a reused account in step with the flow' do
    let(:trigger) { create_trigger(event_types: [scheduled], description: 'nightly').payload }

    def edit(trigger)
      update_trigger(trigger,
        ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled], description: 'renamed')
    end

    it 'follows the flow account up when it is promoted' do
      account = trigger.service_account
      project.member(shared_service_account).update!(access_level: Gitlab::Access::MAINTAINER)

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::MAINTAINER)
    end

    it 'follows the flow account down when it is demoted' do
      account = trigger.service_account
      project.member(shared_service_account).update!(access_level: Gitlab::Access::REPORTER)

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::REPORTER)
    end

    it 'restores membership the dedicated account lost' do
      account = trigger.service_account
      project.member(account).destroy!

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::DEVELOPER)
    end

    it 'leaves the role alone when the flow account is no longer a member' do
      account = trigger.service_account
      project.member(shared_service_account).destroy!

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::DEVELOPER)
    end

    it 'does not follow the flow account to Owner' do
      account = trigger.service_account
      project.member(shared_service_account).update!(access_level: Gitlab::Access::OWNER)

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::DEVELOPER)
    end

    context 'when the role cannot be synced' do
      before do
        allow_next_instance_of(::Ai::FlowTriggers::SyncAutonomousServiceAccountRoleService) do |service|
          allow(service).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'membership refused', reason: :validation_error))
        end
      end

      it 'keeps the edit' do
        result = edit(trigger)

        expect(result).to be_success
        expect(result.payload.description).to eq('renamed')
      end
    end

    context 'when the role sync raises' do
      before do
        allow_next_instance_of(::Ai::FlowTriggers::SyncAutonomousServiceAccountRoleService) do |service|
          allow(service).to receive(:execute).and_raise(ActiveRecord::RecordNotUnique, 'duplicate key')
        end
      end

      it 'keeps the edit and tracks the exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          instance_of(ActiveRecord::RecordNotUnique),
          hash_including(project_id: project.id)
        )

        result = edit(trigger)

        expect(result).to be_success
        expect(result.payload.reload.description).to eq('renamed')
      end
    end

    it 'reconciles only once the trigger change is committed' do
      depth_outside = ApplicationRecord.connection.open_transactions
      depth_during = nil

      allow_next_instance_of(::Ai::FlowTriggers::SyncAutonomousServiceAccountRoleService) do |service|
        allow(service).to receive(:execute) do
          depth_during = ApplicationRecord.connection.open_transactions
          ServiceResponse.success(payload: { changed: false })
        end
      end

      expect(edit(trigger)).to be_success
      expect(depth_during).to eq(depth_outside)
    end

    it 'leaves the role alone when the editor cannot assign it' do
      account = trigger.service_account
      project.member(shared_service_account).update!(access_level: Gitlab::Access::PLANNER)

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::DEVELOPER)
    end

    it 'leaves the role alone when the editor cannot assign the role the account holds' do
      account = trigger.service_account
      project.member(account).update!(access_level: Gitlab::Access::PLANNER)
      project.member(shared_service_account).update!(access_level: Gitlab::Access::REPORTER)

      expect(edit(trigger)).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::PLANNER)
    end

    it 're-levels to a role only an owner can assign when an owner edits' do
      owner = create(:user, owner_of: project)
      account = trigger.service_account
      project.member(shared_service_account).update!(access_level: Gitlab::Access::PLANNER)

      result = Ai::FlowTriggers::UpdateService
        .new(project: project, current_user: owner, trigger: trigger)
        .execute(
          ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled], description: 'renamed by owner'
        )

      expect(result).to be_success
      expect(project.member(account).access_level).to eq(Gitlab::Access::PLANNER)
    end
  end

  it 'keeps the dedicated account when an update omits event_types' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    original = trigger.service_account

    result = update_trigger(trigger, ai_catalog_item_consumer_id: item_consumer.id, description: 'renamed only')

    expect(result).to be_success
    expect(trigger.reload.service_account).to eq(original)
  end

  it 'does not leave a service account behind when the trigger fails validation' do
    result = nil

    expect do
      result = create_trigger(event_types: [scheduled], description: '')
    end.not_to change { service_accounts_without_composite_identity.count }

    # Proves provisioning ran and was rolled back, rather than the trigger
    # failing before an account was ever created.
    expect(result.reason).to eq(:validation_error)
  end

  it 'still rejects one trigger that mixes autonomous and interactive events' do
    result = create_trigger(event_types: [mention, scheduled], description: 'both')

    expect(result).to be_error
    expect(result.message).to include('cannot combine autonomous event types')
  end

  it 'matches the dedicated account to the role the flow account holds' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload

    expect(project.member(shared_service_account).access_level).to eq(Gitlab::Access::DEVELOPER)
    expect(project.member(trigger.service_account).access_level).to eq(Gitlab::Access::DEVELOPER)
  end

  context 'when the flow account is not a member of the project' do
    let!(:existing_trigger) { create_trigger(event_types: [scheduled], description: 'existing').payload }

    before do
      project.member(shared_service_account).destroy!
    end

    it 'refuses to create the trigger' do
      result = create_trigger(event_types: [scheduled], description: 'nightly')

      expect(result).to be_error
      expect(result.message).to include("The flow's service account is not a member of this project")
      expect(result.reason).to eq(:validation_error)
    end

    it 'provisions no account for the refused trigger' do
      expect do
        create_trigger(event_types: [scheduled], description: 'nightly')
      end.not_to change { service_accounts_without_composite_identity.count }
    end

    it 'refuses an update that turns an interactive trigger autonomous' do
      trigger = create_trigger(event_types: [mention], description: 'interactive').payload

      result = update_trigger(trigger,
        ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled])

      expect(result).to be_error
      expect(result.message).to include("The flow's service account is not a member of this project")
      expect(trigger.reload.autonomous_service_account_id).to be_nil
    end

    # A trigger that already owns an account does not need a role to match, so
    # editing it must not start failing because the flow account moved on.
    it 'still allows an update to a trigger that already has an account' do
      result = update_trigger(existing_trigger,
        ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled], description: 'renamed')

      expect(result).to be_success
      expect(existing_trigger.reload.service_account).to eq(existing_trigger.autonomous_service_account)
    end
  end

  it 'revokes the dedicated account project access when the trigger is deleted' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = trigger.service_account

    Ai::FlowTriggers::DestroyService.new(trigger: trigger, current_user: current_user).execute

    expect(project.member(account)).to be_nil
  end

  it 'revokes the dropped account when an update turns the trigger interactive' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = trigger.autonomous_service_account

    result = update_trigger(trigger, ai_catalog_item_consumer_id: item_consumer.id, event_types: [mention])

    expect(result).to be_success
    expect(trigger.reload.autonomous_service_account).to be_nil
    expect(project.member(account)).to be_nil
  end

  it 'gives each autonomous trigger on the same flow its own account' do
    first = create_trigger(event_types: [scheduled], description: 'nightly').payload
    second = create_trigger(event_types: [scheduled], description: 'weekly').payload

    expect(first.autonomous_service_account).to be_present
    expect(second.autonomous_service_account).to be_present
    expect(second.autonomous_service_account).not_to eq(first.autonomous_service_account)
  end

  it 'keeps the dropped account when another trigger still uses it' do
    first = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = first.autonomous_service_account

    second = create_trigger(event_types: [scheduled], description: 'weekly').payload
    second.update!(autonomous_service_account: account)

    update_trigger(first, ai_catalog_item_consumer_id: item_consumer.id, event_types: [mention])

    expect(project.member(account)).to be_present
  end

  it 'keeps the dedicated account a project member while the trigger is paused' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = trigger.autonomous_service_account

    result = update_trigger(trigger, ai_catalog_item_consumer_id: item_consumer.id, active: false)

    expect(result).to be_success
    expect(trigger.reload).not_to be_active
    expect(project.member(account)).to be_present
  end

  it 'keeps the dropped account when only a paused trigger still uses it' do
    first = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = first.autonomous_service_account

    second = create_trigger(event_types: [scheduled], description: 'weekly').payload
    second.update!(autonomous_service_account: account, active: false)

    update_trigger(first, ai_catalog_item_consumer_id: item_consumer.id, event_types: [mention])

    expect(project.member(account)).to be_present
  end

  it 'logs when the membership survives a revocation attempt' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload

    allow_next_instance_of(::Ai::ServiceAccountMemberRemoveService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success)
    end

    expect(::Gitlab::AppLogger).to receive(:warn).with(
      hash_including(
        ::Labkit::Fields::LOG_MESSAGE => 'Failed to revoke the dedicated service account project access',
        ::Labkit::Fields::GL_PROJECT_ID => project.id
      )
    )

    Ai::FlowTriggers::DestroyService.new(trigger: trigger, current_user: current_user).execute
  end

  it 'keeps the update successful when revocation raises, and tracks it' do
    trigger = create_trigger(event_types: [scheduled], description: 'nightly').payload
    account = trigger.autonomous_service_account
    error = StandardError.new('member removal failed')

    allow_next_instance_of(::Ai::ServiceAccountMemberRemoveService) do |service|
      allow(service).to receive(:execute).and_raise(error)
    end

    expect(::Gitlab::ErrorTracking).to receive(:track_exception)
      .with(error, hash_including(project_id: project.id, service_account_id: account.id))
    expect(::Gitlab::AppLogger).to receive(:warn).with(
      hash_including(
        ::Labkit::Fields::LOG_MESSAGE => 'Failed to revoke the dedicated service account project access'
      )
    )

    result = update_trigger(trigger, ai_catalog_item_consumer_id: item_consumer.id, event_types: [mention])

    expect(result).to be_success
    expect(trigger.reload.autonomous_service_account).to be_nil
  end

  it 'names an account after the trigger when the update omits description' do
    trigger = create_trigger(event_types: [mention], description: 'existing name').payload

    result = update_trigger(trigger, ai_catalog_item_consumer_id: item_consumer.id, event_types: [scheduled])

    expect(result).to be_success
    expect(trigger.reload.autonomous_service_account.name).to eq("Duo Scheduled #{project.path} existing name")
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(autonomous_service_account_execution: false)
    end

    it 'rejects the scheduled event type' do
      result = create_trigger(event_types: [scheduled], description: 'nightly')

      expect(result).to be_error
      expect(result.message).to include('scheduled events are not available')
    end
  end
end
