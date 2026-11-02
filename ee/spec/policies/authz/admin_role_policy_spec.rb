# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::AdminRolePolicy, feature_category: :permissions do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:admin_role) { build(:admin_role) }

  subject(:policy) { described_class.new(current_user, admin_role) }

  describe 'various permissions' do
    where(:permission, :license) do
      :read_admin_role    | :custom_roles
      :update_admin_role  | :custom_roles
      :delete_admin_role  | :custom_roles
    end

    include_examples 'permission allowed for admins with the license'
  end
end
