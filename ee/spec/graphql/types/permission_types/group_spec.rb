# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::Group, feature_category: :groups_and_projects do
  specify do
    expected_permissions = %i[
      generate_description
      admin_work_item_lifecycle
      read_runner_cloud_provisioning_info
      read_pro_ai_analytics
      read_enterprise_ai_analytics
      read_orbit_setting
      read_orbit_trial
      start_orbit_trial
      update_knowledge_graph_setting
      read_dora4_analytics
      read_cycle_analytics
      read_security_resource
    ]

    expected_permissions.each do |permission|
      expect(described_class).to have_graphql_field(permission)
    end
  end
end
