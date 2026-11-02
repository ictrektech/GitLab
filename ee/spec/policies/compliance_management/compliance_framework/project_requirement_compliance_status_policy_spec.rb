# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::ComplianceManagement::ComplianceFramework::ProjectRequirementComplianceStatusPolicy,
  feature_category: :compliance_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:framework) { create(:compliance_framework, namespace: group) }
  let_it_be(:requirement) { create(:compliance_requirement, namespace: group, framework: framework) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be(:requirement_status) do
    create(:project_requirement_compliance_status, compliance_requirement: requirement, project: project)
  end

  subject(:policy) { described_class.new(user, requirement_status) }

  it { is_expected.to delegate_to(ComplianceManagement::FrameworkPolicy) }
end
