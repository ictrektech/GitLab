# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::PipelineSecurityReportFinding, feature_category: :vulnerability_management do
  it 'exposes the expected permissions' do
    expected_permissions = %i[admin_vulnerability create_issue confirm_vulnerability dismiss_vulnerability
      resolve_vulnerability revert_vulnerability update_vulnerability_severity]

    expect(described_class).to have_graphql_fields(expected_permissions).only
  end
end
