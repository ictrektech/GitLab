# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::SettingDrift, feature_category: :security_policy_management do
  describe '.from_detail' do
    it 'reads the drifted setting out of its dotted path', :aggregate_failures do
      drift = described_class.from_detail('path' => 'project.settings.request_access_enabled',
        'expected' => false, 'actual' => true)

      expect(drift.setting).to eq('request_access_enabled')
      expect(drift.expected).to be(false)
      expect(drift.actual).to be(true)
    end

    it 'is nil for a detail that names no project setting', :aggregate_failures do
      # A custom Rego rule reports a message alone, and a path under another
      # subject names something this writer does not own.
      expect(described_class.from_detail('message' => 'custom rule')).to be_nil
      expect(described_class.from_detail('path' => 'project.name')).to be_nil
      expect(described_class.from_detail('path' => 'group.settings.whatever')).to be_nil
      expect(described_class.from_detail('path' => 'project.settings.')).to be_nil
      expect(described_class.from_detail(nil)).to be_nil
    end
  end

  describe '#changed_since_evaluation?' do
    it 'is true only when the setting holds a third value now', :aggregate_failures do
      drift = described_class.from_detail('path' => 'project.settings.s', 'expected' => false, 'actual' => true)

      expect(drift.changed_since_evaluation?(false)).to be(true)
      expect(drift.changed_since_evaluation?(true)).to be(false)
    end

    it 'is false when the evaluation did not record the actual value' do
      drift = described_class.from_detail('path' => 'project.settings.s', 'expected' => false)

      expect(drift.changed_since_evaluation?(true)).to be(false)
    end
  end
end
