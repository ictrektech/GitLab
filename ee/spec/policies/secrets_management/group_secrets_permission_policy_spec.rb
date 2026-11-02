# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::GroupSecretsPermissionPolicy, feature_category: :secrets_management do
  subject(:policy) { described_class.new(user, secrets_permission) }

  let_it_be(:user) { build(:user) }
  let_it_be(:group) { build(:group) }
  let_it_be(:secrets_permission) do
    SecretsManagement::GroupSecretsPermission.new(
      resource: group,
      principal_type: 'User',
      principal_id: 1,
      actions: %w[read]
    )
  end

  it { is_expected.to delegate_to(::GroupPolicy) }
end
