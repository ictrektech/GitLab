# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'analytics aggregation engine exclusion filter coverage',
  feature_category: :value_stream_management do
  exact_match = Gitlab::Database::Aggregation::ClickHouse::ExactMatchFilter
  exact_not_match = Gitlab::Database::Aggregation::ClickHouse::ExactNotMatchFilter

  engines = [
    Analytics::AggregationEngines::AgentPlatformSessions,
    Analytics::AggregationEngines::AiUsageEvents,
    Analytics::AggregationEngines::CodeSuggestions,
    Analytics::AggregationEngines::Contributions,
    Analytics::AggregationEngines::Deployments,
    Analytics::AggregationEngines::DuoToolCalls,
    Analytics::AggregationEngines::DuoWorkflows,
    Analytics::AggregationEngines::MergeRequests,
    Analytics::AggregationEngines::Pipelines
  ].freeze

  # Columns deliberately left inclusion-only, as `[engine, column]` pairs. #629296 permits this
  # with a documented reason, so anything added here needs one in review.
  inclusion_only = [
    # A non-nullable boolean needs no exclusion argument: `createdByDuo: false` already says it.
    [Analytics::AggregationEngines::MergeRequests, :created_by_duo],
    # Same for a computed boolean: `authorHuman: false` already says it.
    [Analytics::AggregationEngines::MergeRequests, :author_human],
    # Two events only: `event: tool_failed_duo_chat` already says "not succeeded".
    [Analytics::AggregationEngines::DuoToolCalls, :event]
  ].freeze

  it 'covers every engine in ee/app/models/analytics/aggregation_engines' do
    # Top level only: engine subdirectories hold support classes, not engines.
    on_disk = Dir[Rails.root.join('ee/app/models/analytics/aggregation_engines/*.rb')]
      .map { |path| File.basename(path, '.rb') }

    expect(engines.map { |engine| engine.name.demodulize.underscore }).to match_array(on_disk)
  end

  # Without this, a stale or misspelled allowlist entry subtracts nothing and still reports green.
  it 'has no stale entries in the inclusion_only allowlist' do
    stale = inclusion_only.reject do |engine, column|
      engine.filters.any? { |f| f.instance_of?(exact_match) && f.name == column }
    end

    expect(stale).to be_empty
  end

  engines.each do |engine|
    context "with #{engine.name.demodulize}" do
      let(:described_engine_max) { engine::MAX_EXCLUSION_VALUES }
      let(:included_columns) { engine.filters.select { |f| f.instance_of?(exact_match) }.map(&:name) }
      let(:excluded_columns) { engine.filters.select { |f| f.instance_of?(exact_not_match) }.map(&:name) }
      let(:expected) { included_columns - inclusion_only.filter_map { |e, column| column if e == engine } }

      it 'pairs every exact_match filter with an exact_not_match filter on the same column' do
        expect(excluded_columns).to match_array(expected)
      end

      it 'caps every exclusion filter at MAX_EXCLUSION_VALUES' do
        uncapped = engine.filters
          .select { |f| f.instance_of?(exact_not_match) }
          .reject { |f| f.max_size == described_engine_max }
          .map(&:identifier)

        expect(uncapped).to be_empty
      end

      it 'suffixes every exclusion filter identifier with `_not`' do
        expect(engine.filters.select { |f| f.instance_of?(exact_not_match) }.map(&:identifier))
          .to match_array(expected.map { |column| :"#{column}_not" })
      end
    end
  end
end
