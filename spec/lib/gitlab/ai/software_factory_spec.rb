# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::SoftwareFactory, feature_category: :dap_triggers do
  describe '.enabled?' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:project) { create(:project, group: subgroup) }
    let_it_be(:other_project) { create(:project, group: subgroup) }
    let_it_be(:personal_project) { create(:project) }

    subject(:enabled) { described_class.enabled?(container) }

    context 'with a project' do
      let(:container) { project }

      it { is_expected.to be(true) }

      context 'when dap_software_factory is disabled' do
        before do
          stub_feature_flags(dap_software_factory: false)
        end

        it { is_expected.to be(false) }
      end

      context 'when dap_software_factory is enabled for the top-level group' do
        before do
          stub_feature_flags(dap_software_factory: root_group)
        end

        it { is_expected.to be(true) }
      end

      context 'when dap_software_factory is enabled for the project' do
        before do
          stub_feature_flags(dap_software_factory: project)
        end

        it { is_expected.to be(true) }

        it 'is not enabled for another project of the group' do
          expect(described_class.enabled?(other_project)).to be(false)
        end
      end

      context 'when dap_software_factory is enabled for the parent subgroup only' do
        before do
          stub_feature_flags(dap_software_factory: subgroup)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'with a project in a personal namespace' do
      let(:container) { personal_project }

      before do
        stub_feature_flags(dap_software_factory: personal_project.namespace)
      end

      it { is_expected.to be(true) }
    end

    context 'with a top-level group' do
      let(:container) { root_group }

      context 'when dap_software_factory is enabled for the group' do
        before do
          stub_feature_flags(dap_software_factory: root_group)
        end

        it { is_expected.to be(true) }
      end

      context 'when dap_software_factory is enabled for a project of the group only' do
        before do
          stub_feature_flags(dap_software_factory: project)
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
