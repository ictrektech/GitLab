# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::ProvisionAutonomousServiceAccountService, feature_category: :duo_agent_platform do
  def service_accounts_without_composite_identity
    User.where(user_type: 'service_account', composite_identity_enforced: false)
  end

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:shared_service_account) do
    create(:service_account, provisioned_by_group: group, composite_identity_enforced: true)
  end

  let_it_be(:parent_item_consumer) do
    create(:ai_catalog_item_consumer, :parent_item_consumer, group: group, service_account: shared_service_account)
  end

  let_it_be(:item_consumer) do
    create(:ai_catalog_item_consumer, :for_flow,
      project: project, item: parent_item_consumer.item, parent_item_consumer: parent_item_consumer)
  end

  let(:description) { 'nightly' }
  let(:access_level) { Gitlab::Access::DEVELOPER }

  subject(:result) do
    described_class.new(
      project: project,
      current_user: current_user,
      item_consumer: item_consumer,
      description: description,
      access_level: access_level
    ).execute
  end

  shared_examples 'a refusal that created nothing' do
    it 'reports account_not_provisioned' do
      expect(result.reason).to eq(described_class::ERROR_REASON_NOT_PROVISIONED)
    end
  end

  it 'creates a service account without composite identity' do
    expect(result).to be_success

    service_account = result.payload[:service_account]
    expect(service_account).to be_service_account
    expect(service_account).not_to be_composite_identity_enforced
  end

  it 'provisions the account against the project' do
    expect(::Namespaces::ServiceAccounts::ProjectCreateService).to receive(:new)
      .with(current_user, hash_including(project_id: project.id), uniquify_provided_username: true)
      .and_call_original

    expect(result.payload[:service_account].provisioned_by_project).to eq(project)
  end

  it 'leaves the account unable to create groups or further service accounts' do
    service_account = result.payload[:service_account]

    expect(service_account.sa_provisioned_by_project?).to be(true)
    expect(Ability.allowed?(service_account, :create_group)).to be(false)
    expect(Ability.allowed?(service_account, :create_service_account, project)).to be(false)
  end

  it 'never enables composite identity on the way in' do
    expect(::Namespaces::ServiceAccounts::ProjectCreateService).to receive(:new)
      .with(current_user, hash_including(composite_identity_enforced: false), uniquify_provided_username: true)
      .and_call_original

    expect(result.payload[:service_account]).not_to be_composite_identity_enforced
  end

  context 'when the user cannot create a service account in the project' do
    let_it_be(:developer) { create(:user, developer_of: project) }

    let(:current_user) { developer }
    let(:access_level) { Gitlab::Access::DEVELOPER }

    it 'refuses instead of bypassing the check, in terms of the trigger' do
      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
      expect(result.message).to eq('Scheduled triggers run as their own service account, and you do not ' \
        'have permission to create one in this project')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when the user has a Developer-based custom role with admin_ai_catalog_item_consumer' do
    let_it_be(:custom_role_user) { create(:user) }
    let_it_be(:custom_role) { create(:member_role, :developer, :admin_ai_catalog_item_consumer, namespace: group) }
    let_it_be(:custom_role_membership) do
      create(:project_member, :developer, member_role: custom_role, user: custom_role_user, project: project)
    end

    let(:current_user) { custom_role_user }

    before do
      stub_licensed_features(custom_roles: true)
    end

    it 'refuses because the custom role lacks create_service_account' do
      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
      expect(result.message).to eq('Scheduled triggers run as their own service account, and you do not ' \
        'have permission to create one in this project')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when the instance forbids inviting members' do
    before do
      stub_licensed_features(disable_invite_members: true)
      stub_application_setting(disable_invite_members: true)
    end

    it 'refuses before creating an account that could not join the project' do
      expect(Ability.allowed?(current_user, :create_service_account, project)).to be(true)

      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
      expect(result.message).to eq('Scheduled triggers run as their own service account, and you do not ' \
        'have permission to add one to this project')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  it 'leaves the shared account untouched' do
    result

    expect(shared_service_account.reload).to be_composite_identity_enforced
  end

  it 'adds the account to the project at the given role' do
    member = project.member(result.payload[:service_account])

    expect(member.access_level).to eq(Gitlab::Access::DEVELOPER)
  end

  context 'with a different role' do
    let(:access_level) { Gitlab::Access::REPORTER }

    it 'uses it rather than a hardcoded default' do
      member = project.member(result.payload[:service_account])

      expect(member.access_level).to eq(Gitlab::Access::REPORTER)
    end
  end

  it 'audits the provisioning' do
    expect(Ai::Catalog::ItemConsumers::ServiceAccountProvisionedAuditor).to receive(:new).and_call_original

    result
  end

  context 'with an access level that must not be granted' do
    where(:access_level) do
      [Gitlab::Access::OWNER, Gitlab::Access::PLANNER, Gitlab::Access::SECURITY_MANAGER, 42, nil]
    end

    with_them do
      it 'returns an error without creating an account' do
        expect { result }.not_to change { service_accounts_without_composite_identity.count }
        expect(result).to be_error
        expect(result.message).to include('cannot be granted to an autonomous service account')
      end

      it_behaves_like 'a refusal that created nothing'
    end
  end

  context 'when an Owner provisions a non-hierarchy role they could assign directly' do
    let_it_be(:owner) { create(:user, owner_of: project) }

    let(:current_user) { owner }
    let(:access_level) { Gitlab::Access::PLANNER }

    it 'allows it, matching can_assign_role?' do
      expect(result).to be_success
      expect(project.member(result.payload[:service_account]).access_level).to eq(Gitlab::Access::PLANNER)
    end
  end

  context 'when the role outranks the provisioning user' do
    let_it_be(:reporter) { create(:user, reporter_of: project) }

    let(:current_user) { reporter }
    let(:access_level) { Gitlab::Access::MAINTAINER }

    it 'refuses rather than letting skip_authorization through' do
      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
      expect(result.message).to include('cannot be granted to an autonomous service account')
    end
  end

  context 'when there is no acting user' do
    let(:current_user) { nil }

    where(:access_level) { [Gitlab::Access::MAINTAINER, Gitlab::Access::DEVELOPER] }

    with_them do
      it 'refuses rather than assuming a role for the absent membership' do
        expect { result }.not_to change { service_accounts_without_composite_identity.count }
        expect(result).to be_error
        expect(result.message).to include('cannot be granted to an autonomous service account')
      end
    end

    it 'refuses before reaching member creation' do
      expect(project.team).not_to receive(:add_member)

      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when a non-member with elevated authority provisions' do
    let(:access_level) { Gitlab::Access::PLANNER }

    shared_examples 'provisions at the role can_assign_role? allows' do
      it 'does not cap at Maintainer' do
        expect(project.team.max_member_access(current_user.id)).to eq(Gitlab::Access::NO_ACCESS)
        expect(project.can_assign_role?(current_user, access_level)).to be(true)

        expect(result).to be_success
        expect(project.member(result.payload[:service_account]).access_level).to eq(Gitlab::Access::PLANNER)
      end
    end

    context 'with an instance admin' do
      let_it_be(:admin) { create(:admin) }

      let(:current_user) { admin }

      before do
        stub_application_setting(admin_mode: false)
      end

      it_behaves_like 'provisions at the role can_assign_role? allows'
    end

    context 'with an organization owner' do
      let_it_be(:organization_owner) { create(:organization_owner, organization: project.organization).user }

      let(:current_user) { organization_owner }

      before do
        project.organization.clear_memoization(:owner_user_ids)
      end

      it_behaves_like 'provisions at the role can_assign_role? allows'
    end
  end

  context 'when the group locks project membership' do
    let_it_be(:locked_group) { create(:group, membership_lock: true) }
    let_it_be(:locked_project) { create(:project, group: locked_group) }
    let_it_be(:locked_project_maintainer) { create(:user, maintainer_of: locked_group) }

    let(:project) { locked_project }
    let(:current_user) { locked_project_maintainer }

    it 'returns an error without creating an account' do
      expect { result }.not_to change { service_accounts_without_composite_identity.count }
      expect(result).to be_error
      expect(result.message)
        .to eq('The service account for a scheduled trigger cannot be added as a member of this project')
    end

    it_behaves_like 'a refusal that created nothing'

    it 'still admits a composite account, which the lock exempts' do
      composite = create(:service_account, provisioned_by_group: locked_group, composite_identity_enforced: true)

      member = locked_project.team.add_member(
        composite, Gitlab::Access::DEVELOPER, current_user: locked_project_maintainer, skip_authorization: true
      )

      expect(member).to be_persisted
    end
  end

  context 'with an instance-wide membership lock' do
    before do
      stub_application_setting(lock_memberships_to_ldap: true)
    end

    it 'provisions the account, which the lock exempts' do
      expect(result).to be_success
      expect(project.member?(result.payload[:service_account])).to be(true)
    end
  end

  context 'when the account cannot be created' do
    before do
      allow_next_instance_of(::Namespaces::ServiceAccounts::ProjectCreateService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'nope'))
      end
    end

    it 'returns the failure' do
      expect(result).to be_error
      expect(result.message).to eq('nope')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when the account cannot be added to the project' do
    let(:member) { ProjectMember.new.tap { |m| m.errors.add(:base, 'seat limit reached') } }

    before do
      allow(project.team).to receive(:add_member).and_return(member)
    end

    it "returns the member's errors" do
      expect(result).to be_error
      expect(result.message).to eq('seat limit reached')
    end

    it 'reports membership_failed' do
      expect(result.reason).to eq(described_class::ERROR_REASON_MEMBERSHIP_FAILED)
    end

    context 'when no member is returned at all' do
      let(:member) { nil }

      it 'falls back to a generic message' do
        expect(result).to be_error
        expect(result.message).to eq('Failed to add the service account to the project')
      end
    end
  end

  context 'when the description uses the full trigger limit' do
    let(:description) { 'a' * 255 }

    it 'truncates the name so the last name fits the User limit' do
      expect(result).to be_success

      name = result.payload[:service_account].name
      expect(name).to start_with("Duo Scheduled #{project.path} aaa")
      expect(name.delete_prefix('Duo ').length).to eq(::User::MAX_NAME_LENGTH)
    end

    it 'leaves the username room for a uniqueness suffix' do
      username = result.payload[:service_account].username

      expect(username).to start_with("ai-scheduled-#{project.path}-aaa")
      expect(username.length).to eq(described_class::MAX_USERNAME_LENGTH)
    end
  end

  context 'when the project is missing' do
    let(:project) { nil }

    it 'returns an error without creating an account' do
      expect { result }.not_to change { User.count }

      expect(result).to be_error
      expect(result.message).to eq('Project is required')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when the consumer has no group to provision under' do
    before do
      allow(item_consumer).to receive_messages(group: nil, project: nil)
    end

    it 'returns an error' do
      expect(result).to be_error
      expect(result.message).to include('Project must belong to a group')
    end

    it_behaves_like 'a refusal that created nothing'
  end

  context 'when the consumer belongs to a personal namespace project' do
    let_it_be(:personal_project) { create(:project, namespace: create(:namespace)) }

    before do
      allow(item_consumer).to receive_messages(group: nil, project: personal_project)
    end

    it 'returns an error instead of passing the namespace off as a group' do
      expect(result).to be_error
      expect(result.message).to include('Project must belong to a group')
    end
  end
end
