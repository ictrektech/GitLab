# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::Samplers::GlobalSearchSampler, feature_category: :global_search do
  subject(:sampler) { described_class.new }

  before do
    allow(::ActiveContext).to receive_message_chain(:adapter, :full_collection_name)
      .and_return(ActiveContextHelpers.code_collection_name)
  end

  it_behaves_like 'metrics sampler', 'GLOBAL_SEARCH_SAMPLER'

  describe '#sample' do
    it 'invokes the Elastic::MetricsUpdateService' do
      expect_next_instance_of(::Elastic::MetricsUpdateService) do |service|
        expect(service).to receive(:execute)
      end

      sampler.sample
    end

    it 'invokes the ::Ai::ActiveContext::MetricsUpdateService' do
      expect_next_instance_of(::Ai::ActiveContext::MetricsUpdateService) do |service|
        expect(service).to receive(:execute)
      end

      sampler.sample
    end

    context 'when the ActiveContext metrics update raises' do
      before do
        allow_next_instance_of(::Ai::ActiveContext::MetricsUpdateService) do |service|
          allow(service).to receive(:execute).and_raise(NoMethodError)
        end
      end

      it 'still invokes the Elastic::MetricsUpdateService and does not raise' do
        expect_next_instance_of(::Elastic::MetricsUpdateService) do |service|
          expect(service).to receive(:execute)
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(NoMethodError))

        expect { sampler.sample }.not_to raise_error
      end

      it 'does not stop the sampler thread when invoked through safe_sample' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(NoMethodError))
        expect(sampler).not_to receive(:stop)

        sampler.safe_sample
      end
    end

    context 'when the Elastic metrics update raises' do
      before do
        allow_next_instance_of(::Elastic::MetricsUpdateService) do |service|
          allow(service).to receive(:execute).and_raise(StandardError)
        end
      end

      it 'still invokes the ::Ai::ActiveContext::MetricsUpdateService and does not raise' do
        expect_next_instance_of(::Ai::ActiveContext::MetricsUpdateService) do |service|
          expect(service).to receive(:execute)
        end
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(StandardError))

        expect { sampler.sample }.not_to raise_error
      end
    end
  end
end
