# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::Settings, feature_category: :knowledge_graph do
  describe '.all_settings' do
    it 'returns the frozen settings registry' do
      expect(described_class.all_settings).to eq(described_class::SETTINGS).and be_frozen
    end
  end

  describe 'setting labels' do
    it 'labels the instance-wide Orbit switch' do
      expect(described_class::SETTINGS[:orbit_dap_enabled_by_default][:label].call)
        .to eq(s_('Orbit|Turn on GitLab Orbit in GitLab Duo'))
    end
  end
end
