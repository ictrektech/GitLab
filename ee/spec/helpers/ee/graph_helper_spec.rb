# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::GraphHelper, feature_category: :dora_metrics do
  let(:current_user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, :private) }
  let(:is_feature_licensed) { true }

  before do
    stub_licensed_features(dora4_analytics: is_feature_licensed)
    self.instance_variable_set(:@current_user, current_user)
  end

  describe '#should_render_quality_summary' do
    subject { helper.should_render_quality_summary }

    before do
      self.instance_variable_set(:@project, project)
    end

    context 'when licensed feature is available' do
      before do
        stub_licensed_features(project_quality_summary: true)
      end

      context 'when feature flag is enabled' do
        it { is_expected.to be(true) }
      end

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(project_quality_summary_page: false)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when licensed feature is not available' do
      before do
        stub_licensed_features(project_quality_summary: false)
      end

      it { is_expected.to be(false) }
    end
  end
end
