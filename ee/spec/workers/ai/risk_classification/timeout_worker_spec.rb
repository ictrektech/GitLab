# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RiskClassification::TimeoutWorker, feature_category: :dap_code_review do
  it 'hands queued jobs to the risk assessment worker' do
    expect_next_instance_of(Ai::RiskAssessment::TimeoutWorker) do |worker|
      expect(worker).to receive(:perform).with(1)
    end

    described_class.new.perform(1)
  end
end
