# frozen_string_literal: true

using RSpec::Parameterized::TableSyntax

# Drives the role x realm (SaaS or self-managed) x entitlement state matrix for
# the abilities the Secrets Manager UI reads as booleans (`can_start_trial`,
# `can_enable_add_on`, `can_provision`). Used by the GroupPolicy, ProjectPolicy
# and GlobalPolicy specs, each under a 'Secrets Manager UI abilities matrix'
# describe.
#
# Expected outcomes, for the roles that have the ability at all:
#
#   Ability                                  | Who          | SaaS         | Self-managed
#   -----------------------------------------|--------------|--------------|-------------
#   start_secrets_manager_trial (group)      | Owner, admin | every state  | never
#   enable_secrets_manager_add_on (group)    | Owner, admin | every state  | never
#   start_secrets_manager_trial (instance)   | admin        | never        | every state
#   enable_secrets_manager_add_on (instance) | admin        | never        | every state
#   provision_secrets_manager (group)        | Owner, admin | write states | write states
#   provision_secrets_manager (project)      | Developer+   | write states | write states
#   create_secret (group)                    | Reporter+    | write states | write states
#   create_project_secrets (project)         | Reporter+    | write states | write states
#
# "+" includes admin.
# Subgroups never get the group billing abilities. `create_secret` and
# `create_project_secrets` have no SaaS/self-managed branch, so they are only
# run through the entitlement-state matrix, not the realm wrapper.
module SecretsManagerUiAbilities
  # Every entitlement the policies can see, keyed by the name used in the
  # example descriptions and in the per-ability state lists.
  ENTITLEMENT_STATES = {
    ineligible: { state: :ineligible },
    blocked_trial_expired: { state: :blocked, blocked_reason: :trial_expired },
    blocked_credits_exhausted: { state: :blocked, blocked_reason: :credits_exhausted },
    blocked_on_demand_disabled: { state: :blocked, blocked_reason: :on_demand_disabled },
    blocked_grace: { state: :blocked, blocked_reason: :grace },
    blocked_subscription_grace_period_expired: { state: :blocked, blocked_reason: :subscription_grace_period_expired },
    trial_eligible: { state: :trial_eligible },
    trial_eligible_beta_window_open: { state: :trial_eligible, beta_window_eligible: true, beta_program_ended: false },
    trial_eligible_beta_window_ended: { state: :trial_eligible, beta_window_eligible: true, beta_program_ended: true },
    trial: { state: :trial },
    paid: { state: :paid },
    offline_paid: { state: :offline_paid }
  }.freeze

  EVERY_STATE = ENTITLEMENT_STATES.keys.freeze
  NO_STATE = [].freeze
  # The states where `Entitlement#permits_writes?` is true. A beta-cohort group
  # keeps write access until the beta program ends, even though it is still
  # `trial_eligible`.
  WRITE_STATES = %i[trial paid offline_paid trial_eligible_beta_window_open].freeze
end

# Turns on the license and availability so only the role, realm and
# entitlement decide the outcome. The three Secrets Manager feature flags stay
# unstubbed: RSpec defaults every flag to enabled unless a spec stubs it
# otherwise, and the negative-case examples below stub the ones they need off.
RSpec.shared_context 'with secrets manager UI abilities matrix setup' do
  before do
    stub_licensed_features(native_secrets_management: true)
    allow(::SecretsManagement::Availability).to receive_messages(enabled_for_group?: true, enabled_for_project?: true)
  end
end

# Allowed-role matrices: `role_allows` is the role's answer before the
# entitlement is applied, and "and up" includes admin. Include one in the same
# example group as the `with_them` that consumes it: `with_them` only sees a
# `where` table defined on its own group, never one from a parent.
#
# Each table has the lowest allowed role, the role below it and admin.
# ee/spec/lib/authz/role_definitions_spec.rb checks every role's grants, and
# the entitlement rules never look at the role.
RSpec.shared_context 'with secrets manager allowed roles (owner and up)' do
  where(:current_user, :role_allows) do
    ref(:maintainer) | false
    ref(:owner)      | true
    ref(:admin)      | true
  end
end

RSpec.shared_context 'with secrets manager allowed roles (developer and up)' do
  where(:current_user, :role_allows) do
    ref(:reporter)  | false
    ref(:developer) | true
    ref(:admin)     | true
  end
end

RSpec.shared_context 'with secrets manager allowed roles (reporter and up)' do
  where(:current_user, :role_allows) do
    ref(:guest)    | false
    ref(:reporter) | true
    ref(:admin)    | true
  end
end

# Runs the current role row against every entitlement state. In a permitted
# state the ability follows the role; in any other state nobody has it.
# Expects `policy`, `ability`, `current_user` and `role_allows` from the caller.
RSpec.shared_examples 'secrets manager ability kept by allowed roles only in' do |permitted_states|
  unknown = permitted_states - SecretsManagerUiAbilities::ENTITLEMENT_STATES.keys
  raise ArgumentError, "unknown entitlement states: #{unknown.inspect}" if unknown.any?

  # Nothing is permitted, so the denial doesn't come from the entitlement.
  # One example in the most permissive state is enough.
  if permitted_states.empty?
    context 'when the entitlement state is paid' do
      before do
        stub_secrets_manager_entitlement(state: :paid)
      end

      it 'is disallowed for every role' do
        expect(policy.allowed?(ability)).to be(false)
      end
    end
  else
    SecretsManagerUiAbilities::ENTITLEMENT_STATES.each do |state_name, attrs|
      context "when the entitlement state is #{state_name}" do
        before do
          entitlement = ::SecretsManagement::Entitlement.new(**attrs)
          allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
        end

        if permitted_states.include?(state_name)
          it 'follows the role' do
            expect(policy.allowed?(ability)).to eq(role_allows)
          end
        else
          it 'is disallowed for every role' do
            expect(policy.allowed?(ability)).to be(false)
          end
        end
      end
    end
  end
end

RSpec.shared_examples 'secrets manager ability kept by allowed roles per realm only in' do |saas:, self_managed:|
  context 'when on GitLab.com', :saas do
    it_behaves_like 'secrets manager ability kept by allowed roles only in', saas
  end

  context 'when on self-managed' do
    it_behaves_like 'secrets manager ability kept by allowed roles only in', self_managed
  end
end

RSpec.shared_examples 'secrets manager ability disallowed when admin mode is off' do
  context 'when the admin is not in admin mode' do
    let(:current_user) { admin }

    before do
      stub_secrets_manager_entitlement(state: :paid)
    end

    it { expect(policy.allowed?(ability)).to be(false) }
  end
end

RSpec.shared_examples 'secrets manager ability disallowed without the license' do
  context 'when the license is not available' do
    let(:current_user) { owner }

    before do
      stub_licensed_features(native_secrets_management: false)
      stub_secrets_manager_entitlement(state: :paid)
    end

    it { expect(policy.allowed?(ability)).to be(false) }
  end
end

# `can_provision` on a group or project page. Same rules in both realms: a
# role that gets a default policy at provisioning, so it can write to the scope
# it creates, plus an entitlement that permits writes. Groups stay Owner-only;
# projects pass Developer and up, since they write Maintainer and Developer defaults.
RSpec.shared_examples 'secrets manager provisioning ability' do |allowed_roles = nil|
  include_context(allowed_roles || 'with secrets manager allowed roles (owner and up)')

  with_them :enable_admin_mode do
    it_behaves_like 'secrets manager ability kept by allowed roles per realm only in',
      saas: SecretsManagerUiAbilities::WRITE_STATES,
      self_managed: SecretsManagerUiAbilities::WRITE_STATES
  end

  it_behaves_like 'secrets manager ability disallowed when admin mode is off'
  it_behaves_like 'secrets manager ability disallowed without the license'
end

# `create_secret` / `create_project_secrets`, granted to Reporter and above
# once the entitlement permits writes. Unlike `can_provision`, this is not
# exposed to the frontend: the "New secret" button follows the OpenBao
# `userPermissions.createSecrets` capability; this ability gates the create
# mutation itself.
RSpec.shared_examples 'secrets manager secret-creation ability' do
  include_context 'with secrets manager allowed roles (reporter and up)'

  with_them :enable_admin_mode do
    it_behaves_like 'secrets manager ability kept by allowed roles only in', SecretsManagerUiAbilities::WRITE_STATES
  end

  it_behaves_like 'secrets manager ability disallowed when admin mode is off'
  it_behaves_like 'secrets manager ability disallowed without the license'
end
