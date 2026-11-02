# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MarkdownCache::RefreshWorker, feature_category: :markdown do
  describe 'database health deferral' do
    let(:health_check_block) { described_class.database_health_check_attrs[:block] }

    it 'checks the table of a gitlab_sec job class in its own schema' do
      expect(health_check_block.call(['Vulnerability', 1], :gitlab_main, []))
        .to eq([:gitlab_sec, ['vulnerabilities']])
    end
  end
end
