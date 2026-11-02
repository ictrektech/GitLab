# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::RepresentationInformationPolicy, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:vulnerability) { create(:vulnerability, project: project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:vulnerability_representation_information) do
    create(:vulnerability_representation_information,
      vulnerability: vulnerability,
      project: project,
      resolved_in_commit_sha: 'abc123def456')
  end

  subject { described_class.new(user, vulnerability_representation_information) }

  it { is_expected.to delegate_to(ProjectPolicy) }

  context 'when the security_dashboard feature is disabled' do
    before do
      stub_licensed_features(security_dashboard: false)
    end

    it { expect_disallowed(:read_vulnerability_representation_information) }
  end
end
