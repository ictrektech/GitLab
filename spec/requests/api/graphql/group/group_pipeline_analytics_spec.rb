# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.pipelineAnalytics', :aggregate_failures, :click_house, feature_category: :fleet_visibility do
  include GraphqlHelpers
  include ClickHouseHelpers

  let_it_be_with_reload(:group) { create(:group) } # NOTE: reload is necessary to compute traversal_ids
  # NOTE: reload is necessary to compute traversal_ids
  let_it_be_with_reload(:sub_group) { create(:group, parent: group) }
  let_it_be_with_refind(:project) { create(:project, group: sub_group) }

  let_it_be(:reporter) { create(:user, reporter_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }
  let_it_be(:pipelines_data) do
    current_time = Time.utc(2024, 5, 11)
    common_data = { ref: 'main', source: :pipeline }

    [
      { status: :running, started_at: 35.minutes.before(current_time), duration: 30.minutes, **common_data },
      { status: :success, started_at: 1.day.before(current_time), duration: 30.minutes, ref: 'main2', source: :push },
      { status: :failed, started_at: 5.days.before(current_time), duration: 2.hours, **common_data },
      { status: :canceled, started_at: 4.5.days.before(current_time), duration: 30.minutes, **common_data },
      { status: :failed, started_at: 1.week.before(current_time), duration: 45.minutes, **common_data },
      { status: :skipped, started_at: 7.months.before(current_time), duration: 45.minutes, **common_data }
    ]
  end

  let(:simulated_current_time) { Time.current }
  let(:user) { reporter }
  let(:from_time) { nil }
  let(:to_time) { nil }
  let(:source) { nil }
  let(:ref) { nil }

  let(:period_fields) do
    <<~QUERY
      label
      all: count
      success: count(status: SUCCESS)
      failed: count(status: FAILED)
      other: count(status: OTHER)
    QUERY
  end

  let(:query) do
    graphql_query_for(
      :group, { full_path: sub_group.full_path }, # Query for sub_group to ensure traversal_path filtering works
      query_graphql_field(
        :pipeline_analytics, { from_time: from_time, to_time: to_time, ref: ref, source: source }.compact,
        fields)
    )
  end

  before do
    travel_to simulated_current_time
  end

  subject(:perform_request) do
    post_graphql(query, current_user: user)
  end

  it_behaves_like 'pipeline analytics graphql query', :group

  context 'with pipeline_analytics_siphon flag disabled' do
    before do
      stub_feature_flags(pipeline_analytics_siphon: false)
    end

    it_behaves_like 'pipeline analytics graphql query', :group
  end

  describe 'subgroupFullPaths argument' do
    let_it_be(:sub_group2, freeze: true) { create(:group, parent: group) }
    let_it_be(:project_in_sub_group2, freeze: true) { create(:project, group: sub_group2) }

    let(:user) { reporter }
    let(:fields) { query_graphql_field(:aggregate, {}, 'all: count') }

    let(:pipelines) do
      [
        build_stubbed(:ci_pipeline, :success, project: project, ref: 'main', source: :push,
          created_at: 1.day.ago,
          started_at: 1.day.ago, duration: 30.minutes),
        build_stubbed(:ci_pipeline, :failed, project: project_in_sub_group2, ref: 'main', source: :push,
          created_at: 2.days.ago,
          started_at: 2.days.ago, duration: 1.hour)
      ]
    end

    before do
      insert_ci_pipelines_to_click_house(pipelines)
    end

    context 'when filtering by a specific subgroup' do
      let(:query) do
        graphql_query_for(
          :group, { full_path: group.full_path },
          query_graphql_field(
            :pipeline_analytics, { subgroup_full_paths: [sub_group.full_path] },
            fields)
        )
      end

      it 'returns analytics only for the specified subgroup' do
        perform_request

        expect_graphql_errors_to_be_empty
        aggregate = graphql_data_at(:group, :pipelineAnalytics, :aggregate)
        expect(aggregate).to eq('all' => '1')
      end
    end

    context 'when filtering by multiple subgroups' do
      let(:query) do
        graphql_query_for(
          :group, { full_path: group.full_path },
          query_graphql_field(
            :pipeline_analytics, { subgroup_full_paths: [sub_group.full_path, sub_group2.full_path] },
            fields)
        )
      end

      it 'returns analytics for all specified subgroups' do
        perform_request

        expect_graphql_errors_to_be_empty
        aggregate = graphql_data_at(:group, :pipelineAnalytics, :aggregate)
        expect(aggregate).to eq('all' => '2')
      end
    end

    context 'when subgroupFullPaths exceeds the maximum limit' do
      let(:query) do
        max = Resolvers::Ci::PipelineAnalyticsResolver::MAX_SUBGROUP_PATHS
        paths = Array.new(max + 1) { |i| "#{group.full_path}/sub#{i}" }

        graphql_query_for(
          :group, { full_path: group.full_path },
          query_graphql_field(
            :pipeline_analytics, { subgroup_full_paths: paths },
            fields)
        )
      end

      it 'returns a validation error' do
        perform_request

        expect(graphql_errors).to include(
          a_hash_including('message' => match(/subgroupFullPaths is too long/))
        )
      end
    end
  end

  describe 'nameSearch argument' do
    let_it_be(:project_in_group, freeze: true) { create(:project, group: group) }

    let(:fields) { query_graphql_field(:aggregate, {}, 'all: count') }
    let(:query) do
      graphql_query_for(
        :group, { full_path: group.full_path },
        query_graphql_field(:pipeline_analytics, { name_search: 'tier-1' }, fields)
      )
    end

    let(:pipelines) do
      [project, project_in_group, project_in_group].map.with_index(1) do |pipeline_project, age|
        build_stubbed(:ci_pipeline, :success, project: pipeline_project, ref: 'main', source: :push,
          created_at: age.days.ago, started_at: age.days.ago, duration: 30.minutes)
      end
    end

    before do
      insert_ci_pipelines_to_click_house(pipelines)
      insert_ci_pipeline_metadata_to_siphon([
        { pipeline: pipelines[0], name: 'tier-1' },
        { pipeline: pipelines[1], name: 'tier-1-nightly' },
        { pipeline: pipelines[2], name: 'tier-2' }
      ])
    end

    it 'returns analytics only for matching pipelines across the group' do
      perform_request

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :pipelineAnalytics, :aggregate)).to eq('all' => '2')
    end

    context 'when pipeline_analytics_siphon is disabled' do
      before do
        stub_feature_flags(pipeline_analytics_siphon: false)
      end

      it 'returns an argument error' do
        perform_request

        expect_graphql_errors_to_include(/`nameSearch` requires the `pipeline_analytics_siphon` feature flag/)
        expect(graphql_data_at(:group, :pipelineAnalytics)).to be_nil
      end
    end
  end
end
