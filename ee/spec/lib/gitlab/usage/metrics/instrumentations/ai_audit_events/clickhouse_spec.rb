# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::AiAuditEvents::Clickhouse, feature_category: :audit_events do
  let(:metric_class) do
    Class.new(Gitlab::Usage::Metrics::Instrumentations::GenericMetric) do
      include Gitlab::Usage::Metrics::Instrumentations::AiAuditEvents::Clickhouse
    end
  end

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
  end

  it 'fails fast when the including metric does not implement clickhouse_value' do
    expect { metric_class.new(time_frame: 'all').value }.to raise_error(NotImplementedError)
  end
end
