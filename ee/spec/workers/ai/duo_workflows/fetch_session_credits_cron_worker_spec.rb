# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::FetchSessionCreditsCronWorker, feature_category: :duo_agent_platform do
  describe '#perform' do
    subject(:perform) { described_class.new.perform }

    it_behaves_like 'an idempotent worker'

    it 'does nothing' do
      expect(::Gitlab::ClickHouse).not_to receive(:globally_enabled_for_analytics?)
      expect(::ClickHouse::SyncCursor).not_to receive(:cursor_for)

      expect(perform).to be_nil
    end
  end

  it 'keeps a deprecated pause control so jobs paused before the no-op are resumed' do
    expect(described_class.get_pause_control).to eq(:deprecated)
  end
end
