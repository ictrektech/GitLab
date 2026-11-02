# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Security::MttrOverTimeResolver, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, maintainer_of: group) }

  let(:start_date) { Date.new(2026, 9, 7) }
  let(:end_date) { Date.new(2026, 9, 30) }
  let(:args) { { start_date: start_date, end_date: end_date } }
  let(:context) { { current_user: current_user } }
  let(:lookahead) { positive_lookahead }
  let(:finder_result) { [{ 'start_date' => start_date, 'count' => 0, 'sum_days' => 0.0, 'mttr' => nil }] }
  let(:finder) do
    instance_double(::Search::AdvancedFinders::Security::Vulnerability::MttrOverTimeFinder, execute: finder_result)
  end

  subject(:resolved) { resolve(described_class, obj: group, args: args, ctx: context, lookahead: lookahead) }

  around do |example|
    travel_to(Time.utc(2026, 9, 30, 12)) { example.run }
  end

  before do
    stub_licensed_features(security_dashboard: true)
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    allow(::Search::AdvancedFinders::Security::Vulnerability::MttrOverTimeFinder).to receive(:new).and_return(finder)
  end

  def expect_finder_params(expected)
    expect(::Search::AdvancedFinders::Security::Vulnerability::MttrOverTimeFinder)
      .to receive(:new).with(group, expected).and_return(finder)
  end

  it 'returns the finder result unchanged' do
    expect(resolved).to eq(finder_result)
  end

  it 'passes the date range and both groupings to the finder' do
    expect_finder_params(
      created_after: start_date, created_before: end_date, group_mttr_by: %w[severity report_type]
    )

    resolved
  end

  context 'when the page filters and severity are set' do
    let(:args) { super().merge(severity: %w[critical]) }
    let(:context) { super().merge(project_id: [1], report_type: %w[sast], tracked_ref_ids: [2]) }

    it 'passes them to the finder' do
      expect_finder_params(hash_including(
        project_id: [1], report_type: %w[sast], severity: %w[critical], security_project_tracked_context_id: [2]
      ))

      resolved
    end
  end

  context 'when only bySeverity is selected' do
    before do
      allow(lookahead).to receive(:selects?).with(:by_severity).and_return(true)
      allow(lookahead).to receive(:selects?).with(:by_report_type).and_return(false)
    end

    it 'requests only the severity grouping' do
      expect_finder_params(hash_including(group_mttr_by: %w[severity]))

      resolved
    end
  end

  context 'when no breakdown is selected' do
    let(:lookahead) { negative_lookahead }

    it 'still runs the query, without groupings' do
      expect_finder_params(hash_including(group_mttr_by: []))

      expect(resolved).to eq(finder_result)
    end
  end

  context 'when the security_dashboard_mttr_chart feature flag is disabled' do
    before do
      stub_feature_flags(security_dashboard_mttr_chart: false)
    end

    it 'returns nil without querying' do
      expect(::Search::AdvancedFinders::Security::Vulnerability::MttrOverTimeFinder).not_to receive(:new)

      expect(resolved).to be_nil
    end
  end

  context 'when advanced vulnerability management is not available' do
    before do
      stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
    end

    it 'raises an argument error' do
      expect_graphql_error_to_be_created(
        Gitlab::Graphql::Errors::ArgumentError, 'Require advanced vulnerability management to be enabled!'
      ) { resolved }
    end

    context 'when the security_dashboard_mttr_chart feature flag is disabled' do
      before do
        stub_feature_flags(security_dashboard_mttr_chart: false)
      end

      it 'returns nil instead of raising' do
        expect(resolved).to be_nil
      end
    end
  end

  context 'when resolved for the instance security dashboard' do
    subject(:resolved) { resolve(described_class, obj: nil, args: args, ctx: context, lookahead: lookahead) }

    it 'raises an argument error without querying' do
      expect(::Search::AdvancedFinders::Security::Vulnerability::MttrOverTimeFinder).not_to receive(:new)

      expect_graphql_error_to_be_created(
        Gitlab::Graphql::Errors::ArgumentError, 'Require advanced vulnerability management to be enabled!'
      ) { resolved }
    end
  end

  context 'when the user cannot read security resources' do
    let(:context) { { current_user: create(:user) } }

    it 'raises a resource not available error' do
      expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) { resolved }
    end
  end

  context 'with an invalid date range' do
    using RSpec::Parameterized::TableSyntax

    where(:start_date, :end_date, :message) do
      Date.new(2026, 9, 20) | Date.new(2026, 9, 10) | 'start date cannot be after end date'
      Date.new(2026, 10, 5) | Date.new(2026, 10, 10) | 'start date cannot be in the future'
    end

    with_them do
      it 'raises an argument error' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ArgumentError, message) { resolved }
      end
    end
  end

  context 'when the range spans more than the maximum number of weeks' do
    let(:start_date) { Date.new(2026, 9, 28) - described_class::MAX_WEEKS.weeks }

    it 'raises an argument error' do
      expect_graphql_error_to_be_created(
        Gitlab::Graphql::Errors::ArgumentError, "maximum date range is #{described_class::MAX_WEEKS} weeks"
      ) { resolved }
    end
  end

  context 'when the range spans exactly the maximum number of weeks' do
    let(:start_date) { Date.new(2026, 9, 28) - (described_class::MAX_WEEKS - 1).weeks }

    it 'does not raise' do
      expect { resolved }.not_to raise_error
    end

    context 'when the end date is in the future' do
      let(:end_date) { Date.new(2026, 12, 31) }

      it 'only counts weeks up to the current week' do
        expect { resolved }.not_to raise_error
      end
    end
  end
end
