# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::OrbitServiceConfiguredMetric, feature_category: :service_ping do
  describe '#value' do
    context 'when orbit service is configured' do
      let(:expected_value) { true }

      before do
        stub_config(knowledge_graph: { 'enabled' => true })
      end

      it_behaves_like 'a correct instrumented metric value', { time_frame: 'none', data_source: 'system' }
    end

    context 'when orbit service is not configured' do
      let(:expected_value) { false }

      before do
        stub_config(knowledge_graph: { 'enabled' => false })
      end

      it_behaves_like 'a correct instrumented metric value', { time_frame: 'none', data_source: 'system' }
    end

    context 'when knowledge_graph config is missing' do
      let(:expected_value) { false }

      before do
        allow(Gitlab.config).to receive(:knowledge_graph).and_raise(Gitlab::Configs::MissingConfig)
      end

      it_behaves_like 'a correct instrumented metric value', { time_frame: 'none', data_source: 'system' }
    end
  end
end
