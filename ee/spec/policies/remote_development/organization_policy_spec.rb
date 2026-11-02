# frozen_string_literal: true

require 'spec_helper'

# noinspection RubyArgCount -- https://handbook.gitlab.com/handbook/tools-and-tips/editors-and-ides/jetbrains-ides/tracked-jetbrains-issues/#ruby-31542
RSpec.describe RemoteDevelopment::OrganizationPolicy, feature_category: :workspaces do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:non_org_user) { create(:user) }
  let_it_be(:admin_not_in_admin_mode) { create(:user, :admin) }

  where(:user) { [ref(:non_org_user), ref(:admin_not_in_admin_mode)] }

  with_them do
    subject(:policy_instance) { Organizations::OrganizationPolicy.new(user, organization) }

    it "denies mapping permissions" do
      expect_disallowed(:admin_organization_cluster_agent_mapping, :create_cluster_agent_mapping,
        :delete_cluster_agent_mapping, :read_organization_cluster_agent_mapping)
    end
  end
end
