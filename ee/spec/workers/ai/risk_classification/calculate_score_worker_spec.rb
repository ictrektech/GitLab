# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RiskClassification::CalculateScoreWorker, feature_category: :dap_code_review do
  it 'hands queued jobs to the risk assessment worker' do
    expect_next_instance_of(Ai::RiskAssessment::CalculateScoreWorker) do |worker|
      expect(worker).to receive(:perform).with(1, 'sha', { 'claims' => {} }, 2)
    end

    described_class.new.perform(1, 'sha', { 'claims' => {} }, 2)
  end
end
