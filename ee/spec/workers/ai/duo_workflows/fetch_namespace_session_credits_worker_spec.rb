# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::FetchNamespaceSessionCreditsWorker, feature_category: :duo_agent_platform do
  describe '#perform' do
    let(:job_args) { [42, [1, 2, 3]] }

    subject(:perform) { described_class.new.perform(*job_args) }

    it_behaves_like 'an idempotent worker'

    it 'does nothing' do
      expect(::Gitlab::ClickHouse).not_to receive(:globally_enabled_for_analytics?)
      expect(::Gitlab::HTTP).not_to receive(:post)

      expect(perform).to be_nil
    end
  end

  it 'keeps a deprecated pause control so jobs paused before the no-op are resumed' do
    expect(described_class.get_pause_control).to eq(:deprecated)
  end
end
