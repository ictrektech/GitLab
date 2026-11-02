# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ExportPolicy, feature_category: :vulnerability_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:author) { create(:user) }
  let_it_be(:user_vulnerability_export) do
    create(:vulnerability_export, :finished, :csv, :with_csv_file,
      project: project, author: user, organization: project.organization)
  end

  let_it_be(:other_vulnerability_export) do
    create(:vulnerability_export, :finished, :csv, :with_csv_file,
      project: project, author: author, organization: project.organization)
  end

  subject { described_class.new(user, vulnerability_export) }

  describe 'delegation' do
    subject(:policy) { described_class.new(user, export) }

    context 'when the export is for a project' do
      let(:export) { build_stubbed(:vulnerability_export, project: project) }

      it { is_expected.to delegate_to(ProjectPolicy) }
    end

    context 'when the export is for a group' do
      let(:export) { build_stubbed(:vulnerability_export, project: nil, group: build_stubbed(:group)) }

      it { is_expected.to delegate_to(GroupPolicy) }
    end

    context 'when the export is for the instance security dashboard' do
      let(:export) { build_stubbed(:vulnerability_export, project: nil, group: nil, author: author) }

      it { is_expected.to delegate_to(InstanceSecurityDashboardPolicy) }
    end
  end

  context 'when security dashboard is licensed' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'with a user that is an author of vulnerability export' do
      let(:vulnerability_export) { user_vulnerability_export }

      context 'when user has access to vulnerabilities from the project' do
        before_all do
          project.add_developer(user)
        end

        it { expect_allowed(:read_vulnerability_export) }
      end

      context 'when user has no access to vulnerabilities from the project' do
        it { expect_disallowed(:read_vulnerability_export) }
      end
    end

    context 'with a user that is not an author of vulnerability export' do
      let(:vulnerability_export) { other_vulnerability_export }

      before_all do
        project.add_developer(user)
      end

      it { expect_disallowed(:read_vulnerability_export) }
    end
  end

  context 'when security dashboard is not licensed' do
    let(:vulnerability_export) { user_vulnerability_export }

    before_all do
      project.add_developer(user)
    end

    before do
      stub_licensed_features(security_dashboard: false)
    end

    it { expect_disallowed(:read_vulnerability_export) }
  end
end
