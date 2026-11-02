# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ArchiveExportPolicy, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:user_archive_export) { create(:vulnerability_archive_export, project: project, author: user) }
  let_it_be(:other_archive_export) { create(:vulnerability_archive_export, project: project, author: create(:user)) }

  subject { described_class.new(user, archive_export) }

  it { expect(described_class.new(user, user_archive_export)).to delegate_to(ProjectPolicy) }

  context 'when security dashboard is licensed' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when the user is the author of the archive export' do
      let(:archive_export) { user_archive_export }

      context 'when user has access to vulnerabilities from the project' do
        before_all do
          project.add_developer(user)
        end

        it { expect_allowed(:read_vulnerability_archive_export) }
      end

      context 'when user has no access to vulnerabilities from the project' do
        it { expect_disallowed(:read_vulnerability_archive_export) }
      end
    end

    context 'when the user is not the author of the archive export' do
      let(:archive_export) { other_archive_export }

      before_all do
        project.add_developer(user)
      end

      it { expect_disallowed(:read_vulnerability_archive_export) }
    end
  end

  context 'when security dashboard is not licensed' do
    let(:archive_export) { user_archive_export }

    before_all do
      project.add_developer(user)
    end

    before do
      stub_licensed_features(security_dashboard: false)
    end

    it { expect_disallowed(:read_vulnerability_archive_export) }
  end
end
