# frozen_string_literal: true

# The EE initializer configures the ActiveRecord repository in every environment,
# so examples reach the same backend production does and the database rollback
# between them is what leaves the store empty. So `create_policy` must not be called from
# `let_it_be`: that writes outside the per-example transaction and leaks the policy into
# every later example in the file.
RSpec.shared_context 'with policy store helpers' do
  def create_policy(**attributes)
    ::Gitlab::PolicyStore.create(attributes) # rubocop:disable Rails/SaveBang -- not ActiveRecord; the store has no create!
  end
end

RSpec.shared_context 'with the policy store experiment active' do
  before do
    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: true)
  end

  # The instance-wide gates above make the experiment available; the
  # organization additionally has to opt in, the way a group does.
  def opt_organization_into_policy_store!(organization)
    ::Organizations::OrganizationSetting.for(organization.id).update!(
      policy_store_experiment_enabled: true
    )
  end
end

# Sets up an organization with an owner (authorized to manage policies), a
# non-owner member (not authorized), and an owner of an unrelated organization
# (not authorized either; ownership does not cross organizations).
# `current_user` defaults to the owner. `container` defaults to the organization;
# override with `let(:container) { group }` for group-scoped tests.
RSpec.shared_context 'with policy store service authorization' do
  include_context 'with the policy store experiment active'

  let_it_be_with_reload(:organization) { create(:organization) }

  # Default container is the organization. Override in group-scoped tests.
  let(:container) { organization }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_owner) { create(:user) }
  let_it_be(:foreign_organization) { create(:organization) }
  let_it_be(:foreign_org_owner) { create(:user) }

  let(:current_user) { owner }

  before_all do
    create(:organization_user, :owner, organization: organization, user: owner)
    create(:organization_user, organization: organization, user: non_owner)
    create(:organization_user, :owner, organization: foreign_organization, user: foreign_org_owner)
  end

  before do
    opt_organization_into_policy_store!(organization)
  end
end

RSpec.configure do |config|
  config.include_context 'with policy store helpers', :policy_store
end

RSpec.shared_context 'with a policy store group builder' do
  # let_it_be freezes the record it returns, so the opt-in and the owner have to be set here.
  def create_policy_store_group(organization, owner: nil)
    create(:group, organization: organization).tap do |group|
      group.namespace_settings.update!(policy_store_experiment_enabled: true)
      group.add_owner(owner) if owner
    end
  end
end

# A root group inside the organization, opted into the experiment, with its own
# Owner, who holds the group-level *_govern_policy abilities without owning the
# organization. `other_group` exists so cross-namespace isolation can be
# asserted. Include after 'with policy store service authorization'.
RSpec.shared_context 'with policy store group containers' do
  include_context 'with a policy store group builder'

  let_it_be(:group_owner) { create(:user) }
  let_it_be(:group) { create_policy_store_group(organization, owner: group_owner) }
  let_it_be(:other_group) { create_policy_store_group(organization) }
end

# GitLab.com groups without their own organization share the default one, so
# tenant isolation is asserted against it.
RSpec.shared_context 'with the default organization as the policy store container' do
  include_context 'with the policy store experiment active'
  include_context 'with a policy store group builder'

  # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- the default organization is what the tenant isolation applies to
  let_it_be(:default_organization) { create(:organization, :default) }
  # rubocop:enable Gitlab/RSpec/AvoidCreateDefaultOrganization

  let_it_be(:default_organization_owner) do
    create(:user, :organization_owner, organizations: [default_organization])
  end

  let_it_be(:default_organization_group) do
    create_policy_store_group(default_organization, owner: default_organization_owner)
  end

  let(:container) { default_organization }
  let(:current_user) { default_organization_owner }

  before_all do
    opt_organization_into_policy_store!(default_organization)
  end
end
