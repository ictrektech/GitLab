# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dependencies::DependencyListExportPolicy, feature_category: :vulnerability_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:dependency_list_export) { create(:dependency_list_export, author: author, project: project) }

  subject { described_class.new(user, dependency_list_export) }

  describe 'delegation' do
    subject(:policy) { described_class.new(user, export) }

    context 'when the export is for a pipeline' do
      let(:export) { build_stubbed(:dependency_list_export, project: nil, pipeline: build_stubbed(:ci_pipeline)) }

      it { is_expected.to delegate_to(Ci::PipelinePolicy) }
    end

    context 'when the export is for a project' do
      let(:export) { build_stubbed(:dependency_list_export, project: project) }

      it { is_expected.to delegate_to(ProjectPolicy) }
    end

    context 'when the export is for a group' do
      let(:export) { build_stubbed(:dependency_list_export, project: nil, group: build_stubbed(:group)) }

      it { is_expected.to delegate_to(GroupPolicy) }
    end
  end

  context 'when dependency_scanning is licensed' do
    before do
      stub_licensed_features(dependency_scanning: true)
    end

    context 'when the user is author of the export' do
      let(:author) { user }

      context 'when user can read the project dependencies' do
        before do
          project.add_developer(user)
        end

        it { is_expected.to be_allowed(:read_dependency_list_export) }
      end

      context 'when user can not read the project dependencies' do
        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end
    end

    context 'when the user is not author of the export' do
      let(:author) { create(:user) }

      context 'when user can read the project dependencies' do
        before do
          project.add_developer(user)
        end

        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end

      context 'when user can not read the project dependencies' do
        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end
    end
  end

  context 'when dependency_scanning is not licensed' do
    before do
      stub_licensed_features(dependency_scanning: false)
    end

    context 'when the user is author of the export' do
      let(:author) { user }

      context 'when user can read the project dependencies' do
        before do
          project.add_developer(user)
        end

        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end

      context 'when user can not read the project dependencies' do
        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end
    end

    context 'when the user is not author of the export' do
      let(:author) { create(:user) }

      context 'when user can read the project dependencies' do
        before do
          project.add_developer(user)
        end

        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end

      context 'when user can not read the project dependencies' do
        it { is_expected.to be_disallowed(:read_dependency_list_export) }
      end
    end
  end
end
