# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Subscriptions::DroppedEvents, feature_category: :api do
  describe '.count' do
    let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

    before do
      allow(described_class).to receive(:counter).and_return(counter)
    end

    it 'counts the events under the snake_case subscription name' do
      described_class.count('namespaceWorkItemChanges', :rate_limited, 2)

      expect(counter).to have_received(:increment)
        .with({ subscription: 'namespace_work_item_changes', reason: 'rate_limited' }, 2)
    end
  end
end
