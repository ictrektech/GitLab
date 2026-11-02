# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::AggregationEngines::MergeRequests, :click_house, time_travel_to: '2026-01-30',
  type: :aggregation_engine,
  feature_category: :value_stream_management do
  let(:engine) { described_class.new(context: engine_context) }
  let(:engine_context) { { scope: ClickHouse::Client::QueryBuilder.new(described_class.table_name) } }

  let_it_be(:project1) { create(:project) }

  let(:state) { MergeRequest.available_states }

  def metric_key(identifier, parameters: {})
    described_class.metrics.find { |metric| metric.identifier == identifier }
      .instance_key(parameters: parameters).to_sym
  end

  before do
    insert_merge_requests_to_click_house(merge_requests_data, default_project: project1)
  end

  describe '.prepare_base_aggregation_scope' do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project_in_group) { create(:project, group: group) }
    let_it_be(:project_in_subgroup) { create(:project, group: subgroup) }
    let_it_be(:other_project) { create(:project) }

    let(:merge_requests_data) do
      [
        { id: 1, project: project_in_group, state_id: state[:opened], created_at: 10.days.ago },
        { id: 2, project: project_in_subgroup, state_id: state[:opened], created_at: 10.days.ago },
        { id: 3, project: other_project, state_id: state[:opened], created_at: 10.days.ago }
      ]
    end

    subject(:result) do
      scope = described_class.prepare_base_aggregation_scope(send(scope_key))
      ClickHouse::Client.select(scope, :main)
    end

    where(:scope_key, :expected_ids) do
      [
        [:project_in_group,    [1]],
        [:group,               [1, 2]],
        [:subgroup,            [2]],
        [:other_project,       [3]]
      ]
    end

    with_them do
      it 'returns records scoped to the provided context object' do
        expect(result.map { |r| r['id'] }).to match_array(expected_ids)
      end
    end

    context 'with no scope objects' do
      it 'raises an ArgumentError' do
        expect { described_class.prepare_base_aggregation_scope([]) }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'versioning' do
    let(:merge_requests_data) do
      [
        { id: 1, state_id: state[:opened], created_at: 10.days.ago,
          _siphon_replicated_at: 10.days.ago },
        { id: 1, state_id: state[:merged], created_at: 10.days.ago, metric_merged_at: 9.days.ago,
          _siphon_replicated_at: 9.days.ago },
        { id: 2, state_id: state[:opened], created_at: 10.days.ago,
          _siphon_replicated_at: 10.days.ago },
        { id: 2, state_id: state[:closed], created_at: 10.days.ago,
          _siphon_replicated_at: 9.days.ago, _siphon_deleted: true }
      ]
    end

    it 'aggregates only the latest non-deleted version per primary key' do
      request = {
        dimensions: [{ identifier: :state_id }],
        metrics: [{ identifier: :total_count }]
      }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { state_id: 'merged', total_count: 1 }
      ]))
    end
  end

  describe 'dimensions' do
    describe 'author_id' do
      let(:merge_requests_data) do
        [
          { id: 1, author_id: 1, state_id: state[:opened], created_at: 10.days.ago },
          { id: 2, author_id: 1, state_id: state[:opened], created_at: 10.days.ago },
          { id: 3, author_id: 2, state_id: state[:opened], created_at: 10.days.ago },
          { id: 4, state_id: state[:opened], created_at: 10.days.ago }
        ]
      end

      it 'groups merge requests by author_id' do
        request = {
          dimensions: [{ identifier: :author_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { author_id: 1,   total_count: 2 },
          { author_id: 2,   total_count: 1 },
          { author_id: nil, total_count: 1 }
        ]))
      end

      it 'groups merge requests by author_id with author request' do
        request = {
          dimensions: [{ identifier: :author }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { author_id: 1,   total_count: 2 },
          { author_id: 2,   total_count: 1 },
          { author_id: nil, total_count: 1 }
        ]))
      end
    end

    describe 'project_id' do
      let_it_be(:project2) { create(:project) }

      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:opened], created_at: 10.days.ago },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago },
          { id: 3, project: project2, state_id: state[:opened], created_at: 10.days.ago }
        ]
      end

      it 'groups merge requests by target project' do
        request = {
          dimensions: [{ identifier: :project_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, total_count: 2 },
          { project_id: project2.id, total_count: 1 }
        ]))
      end

      it 'groups merge requests by target project with project request' do
        request = {
          dimensions: [{ identifier: :project }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, total_count: 2 },
          { project_id: project2.id, total_count: 1 }
        ]))
      end
    end

    describe 'group_id' do
      let_it_be(:top_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: top_group) }
      let_it_be(:top_group_project) { create(:project, group: top_group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }
      let_it_be(:other_group_project) { create(:project, group: create(:group)) }

      let(:merge_requests_data) do
        [
          { id: 1, project: subgroup_project,    state_id: state[:opened], created_at: 10.days.ago },
          { id: 2, project: subgroup_project,    state_id: state[:opened], created_at: 10.days.ago },
          { id: 3, project: top_group_project,   state_id: state[:opened], created_at: 10.days.ago },
          { id: 4, project: other_group_project, state_id: state[:opened], created_at: 10.days.ago }
        ]
      end

      it 'groups merge requests by top-level group by default' do
        request = {
          dimensions: [{ identifier: :group_id }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { group_id: top_group.id, total_count: 3 },
          { group_id: other_group_project.namespace_id, total_count: 1 }
        ]))
      end

      it 'groups merge requests by the group at the requested depth' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 2 } }],
          metrics: [{ identifier: :total_count }]
        }

        # Projects directly under a top-level group bucket by their project namespace at depth 2.
        expect(engine).to execute_aggregation(request).and_return(match_array([
          { group_id_2: subgroup.id, total_count: 2 },
          { group_id_2: top_group_project.project_namespace_id, total_count: 1 },
          { group_id_2: other_group_project.project_namespace_id, total_count: 1 }
        ]))
      end

      it 'groups merge requests by group_id with group request' do
        request = {
          dimensions: [{ identifier: :group }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { group_id: top_group.id, total_count: 3 },
          { group_id: other_group_project.namespace_id, total_count: 1 }
        ]))
      end

      it 'returns a single null bucket for a depth deeper than the hierarchy' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 4 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ group_id_4: nil, total_count: 4 }])
      end

      it 'returns a validation error for a depth outside the allowed range' do
        request = {
          dimensions: [{ identifier: :group_id, parameters: { depth: 0 } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).with_errors(
          array_including(a_string_matching(/Invalid value\(s\) for parameter `depth`: 0/))
        )
      end
    end

    describe 'created_by_duo' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 10.days.ago, created_by_duo: true },
          { id: 2, state_id: state[:opened], created_at: 10.days.ago, created_by_duo: true },
          { id: 3, state_id: state[:merged], created_at: 10.days.ago }
        ]
      end

      it 'groups merge requests by whether Duo created them' do
        request = {
          dimensions: [{ identifier: :created_by_duo }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_by_duo: true,  total_count: 2 },
          { created_by_duo: false, total_count: 1 }
        ]))
      end
    end

    describe 'created_at' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:opened], created_at: 10.days.ago },
          { id: 2, state_id: state[:opened], created_at: 10.days.ago },
          { id: 3, state_id: state[:opened], created_at: 100.days.ago }
        ]
      end

      it 'groups merge requests by monthly buckets by default' do
        request = {
          dimensions: [{ identifier: :created_at }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_at: 10.days.ago.beginning_of_month,  total_count: 2 },
          { created_at: 100.days.ago.beginning_of_month, total_count: 1 }
        ]))
      end

      it 'groups merge requests by daily buckets' do
        request = {
          dimensions: [{ identifier: :created_at, parameters: { granularity: 'daily' } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { created_at_granularity_daily: 10.days.ago.beginning_of_day,  total_count: 2 },
          { created_at_granularity_daily: 100.days.ago.beginning_of_day, total_count: 1 }
        ]))
      end
    end

    describe 'metric_merged_at' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 20.days.ago, metric_merged_at: 10.days.ago },
          { id: 2, state_id: state[:merged], created_at: 20.days.ago, metric_merged_at: 10.days.ago },
          { id: 3, state_id: state[:merged], created_at: 110.days.ago, metric_merged_at: 100.days.ago }
        ]
      end

      it 'groups merge requests by monthly merge time buckets by default' do
        request = {
          dimensions: [{ identifier: :metric_merged_at }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { metric_merged_at: 10.days.ago.beginning_of_month,  total_count: 2 },
          { metric_merged_at: 100.days.ago.beginning_of_month, total_count: 1 }
        ]))
      end

      it 'groups merge requests by daily merge time buckets' do
        request = {
          dimensions: [{ identifier: :metric_merged_at, parameters: { granularity: 'daily' } }],
          metrics: [{ identifier: :total_count }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { metric_merged_at_granularity_daily: 10.days.ago.beginning_of_day,  total_count: 2 },
          { metric_merged_at_granularity_daily: 100.days.ago.beginning_of_day, total_count: 1 }
        ]))
      end
    end
  end

  describe 'metrics' do
    describe 'time_to_merge_quantile' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 100.seconds },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 200.seconds },
          { id: 3, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 300.seconds }
        ]
      end

      it 'calculates time to merge quantile in milliseconds' do
        request = {
          metrics: [{ identifier: :time_to_merge_quantile, parameters: { quantile: 0.5 } }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { metric_key(:time_to_merge_quantile, parameters: { quantile: 0.5 }) => 200_000.0 }
        ])
      end

      context 'when metric_merged_at is NULL' do
        let(:merge_requests_data) do
          [{ id: 1, state_id: state[:opened], created_at: 10.days.ago, metric_merged_at: nil }]
        end

        it 'returns nil for the quantile' do
          request = {
            metrics: [{ identifier: :time_to_merge_quantile, parameters: { quantile: 0.5 } }]
          }

          expect(engine).to execute_aggregation(request).and_return([
            { metric_key(:time_to_merge_quantile, parameters: { quantile: 0.5 }) => nil }
          ])
        end
      end
    end

    describe 'acceptance_rate' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 10.days.ago, metric_merged_at: 9.days.ago },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago, metric_merged_at: 9.days.ago },
          { id: 3, state_id: state[:closed], created_at: 10.days.ago },
          { id: 4, state_id: state[:opened], created_at: 10.days.ago }
        ]
      end

      it 'calculates the share of merged merge requests' do
        request = { metrics: [{ identifier: :acceptance_rate }] }

        expect(engine).to execute_aggregation(request).and_return([
          { acceptance_rate: 0.5 }
        ])
      end

      context 'when filtered to Duo-created merge requests and bucketed by creation date' do
        let(:merge_requests_data) do
          [
            { id: 1, state_id: state[:merged], created_at: 10.days.ago, metric_merged_at: 9.days.ago,
              created_by_duo: true },
            { id: 2, state_id: state[:opened], created_at: 10.days.ago, created_by_duo: true },
            { id: 3, state_id: state[:merged], created_at: 100.days.ago, metric_merged_at: 99.days.ago,
              created_by_duo: true },
            { id: 4, state_id: state[:closed], created_at: 10.days.ago },
            { id: 5, state_id: state[:closed], created_at: 100.days.ago }
          ]
        end

        it 'reports the Duo acceptance rate trend' do
          request = {
            dimensions: [{ identifier: :created_at }],
            metrics: [{ identifier: :acceptance_rate }],
            filters: [{ identifier: :created_by_duo, values: true }]
          }

          expect(engine).to execute_aggregation(request).and_return(match_array([
            { created_at: 10.days.ago.beginning_of_month,  acceptance_rate: 0.5 },
            { created_at: 100.days.ago.beginning_of_month, acceptance_rate: 1.0 }
          ]))
        end
      end
    end

    describe 'time_to_merge measurement' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 100.seconds },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 200.seconds },
          { id: 3, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 300.seconds }
        ]
      end

      it 'calculates all measurement aggregates in one request' do
        request = {
          metrics: [
            { identifier: :"time_to_merge.min" },
            { identifier: :"time_to_merge.max" },
            { identifier: :"time_to_merge.mean" },
            { identifier: :"time_to_merge.quantile", parameters: { quantile: 0.5 } },
            { identifier: :"time_to_merge.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            time_to_merge__min: 100,
            time_to_merge__max: 300,
            time_to_merge__mean: 200.0,
            metric_key(:"time_to_merge.quantile", parameters: { quantile: 0.5 }) => 200.0,
            time_to_merge__sum: 600
          }
        ])
      end
    end

    describe 'code_review_time measurement' do
      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:merged], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 100.seconds, metric_merged_at: 10.days.ago + 400.seconds },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 100.seconds, metric_merged_at: 10.days.ago + 700.2.seconds },
          # Merged without a review comment
          { id: 3, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 500.seconds },
          # Commented but not merged
          { id: 4, state_id: state[:opened], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 100.seconds },
          # First commented after the merge
          { id: 5, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 100.seconds, metric_first_comment_at: 9.days.ago }
        ]
      end

      it 'calculates review time in rounded-up seconds, excluding unreviewed and unmerged merge requests' do
        request = {
          metrics: [
            { identifier: :"code_review_time.min" },
            { identifier: :"code_review_time.max" },
            { identifier: :"code_review_time.mean" },
            { identifier: :"code_review_time.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            code_review_time__min: 300,
            code_review_time__max: 601,
            code_review_time__mean: 450.5,
            code_review_time__sum: 901
          }
        ])
      end
    end

    describe 'time_to_first_review measurement' do
      let_it_be(:project2) { create(:project) }

      let(:merge_requests_data) do
        [
          { id: 1, state_id: state[:opened], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 100.seconds },
          { id: 2, state_id: state[:merged], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 250.5.seconds, metric_merged_at: 9.days.ago },
          # Never commented on
          { id: 3, state_id: state[:merged], created_at: 10.days.ago, metric_merged_at: 9.days.ago },
          { id: 4, state_id: state[:opened], created_at: 40.days.ago,
            metric_first_comment_at: 40.days.ago + 50.seconds },
          { id: 5, project: project2, state_id: state[:opened], created_at: 10.days.ago,
            metric_first_comment_at: 10.days.ago + 60.seconds },
          # First commented after the merge
          { id: 6, state_id: state[:merged], created_at: 10.days.ago,
            metric_merged_at: 10.days.ago + 100.seconds, metric_first_comment_at: 9.days.ago }
        ]
      end

      it 'calculates time to first review in rounded-up seconds, excluding never-commented merge requests ' \
        'and comments posted after the merge' do
        request = {
          metrics: [
            { identifier: :"time_to_first_review.min" },
            { identifier: :"time_to_first_review.max" },
            { identifier: :"time_to_first_review.mean" },
            { identifier: :"time_to_first_review.sum" }
          ]
        }

        expect(engine).to execute_aggregation(request).and_return([
          {
            time_to_first_review__min: 50,
            time_to_first_review__max: 251,
            time_to_first_review__mean: 115.25,
            time_to_first_review__sum: 461
          }
        ])
      end

      it 'slices time to first review by project and creation month' do
        request = {
          dimensions: [{ identifier: :project_id }, { identifier: :created_at }],
          metrics: [{ identifier: :"time_to_first_review.mean" }]
        }

        expect(engine).to execute_aggregation(request).and_return(match_array([
          { project_id: project1.id, created_at: 10.days.ago.beginning_of_month, time_to_first_review__mean: 175.5 },
          { project_id: project1.id, created_at: 40.days.ago.beginning_of_month, time_to_first_review__mean: 50.0 },
          { project_id: project2.id, created_at: 10.days.ago.beginning_of_month, time_to_first_review__mean: 60.0 }
        ]))
      end
    end
  end

  describe 'filters' do
    let(:merge_requests_data) do
      [
        { id: 1, author_id: 1, state_id: state[:opened], target_branch: 'main',    created_at: 10.days.ago },
        { id: 2, author_id: 1, state_id: state[:merged], target_branch: 'main',    created_at: 100.days.ago,
          metric_merged_at: 100.days.ago, created_by_duo: true },
        { id: 3, author_id: 2, state_id: state[:closed], target_branch: 'develop', created_at: 10.days.ago }
      ]
    end

    describe 'author_id' do
      it 'filters by single author Global ID' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :author_id, values: 'gid://gitlab/User/1' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end

      it 'filters by multiple author Global IDs' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :author_id, values: %w[gid://gitlab/User/1 gid://gitlab/User/2] }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 3 }
        ])
      end
    end

    describe 'target_branch' do
      it 'filters by target branch' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :target_branch, values: 'main' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end

      it 'filters by multiple target branches' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :target_branch, values: %w[main develop] }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 3 }
        ])
      end
    end

    describe 'state_id' do
      it 'filters by state name string' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id, values: 'merged' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 1 }
        ])
      end

      it 'filters by multiple state name strings' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id, values: %w[opened closed] }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end

      it 'returns no results when all state names are unrecognized' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id, values: 'invalid' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 0 }
        ])
      end

      it 'silently drops unrecognized state names mixed with valid ones' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id, values: %w[merged invalid] }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 1 }
        ])
      end
    end

    describe 'created_by_duo' do
      it 'filters merge requests created by Duo' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :created_by_duo, values: true }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 1 }
        ])
      end

      it 'filters merge requests not created by Duo' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :created_by_duo, values: false }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end
    end

    describe 'author_human' do
      let(:user_type) { HasUserType::USER_TYPES }
      let(:non_human_types) { user_type.keys - ['human'] }
      let(:human_id) { 1 }
      let(:deleted_bot_id) { 2 }
      let(:bot_retyped_to_human_id) { 3 }
      let(:human_retyped_to_bot_id) { 4 }
      let(:non_human_ids) { non_human_types.each_index.map { |index| 100 + index } }

      let(:merge_requests_data) do
        author_ids = [human_id, deleted_bot_id, bot_retyped_to_human_id, human_retyped_to_bot_id, nil, *non_human_ids]

        author_ids.each_with_index.map do |author_id, index|
          { id: index + 1, author_id: author_id, state_id: state[:opened], created_at: 10.days.ago }
        end
      end

      before do
        user_row = ->(id, type, deleted: false, minute: 0) do
          { id: id, user_type: user_type[type], _siphon_deleted: deleted,
            _siphon_replicated_at: 10.days.ago + minute.minutes }
        end

        clickhouse_fixture(:siphon_users, [
          user_row.call(human_id, :human),
          user_row.call(deleted_bot_id, :project_bot, deleted: true),
          user_row.call(bot_retyped_to_human_id, :project_bot),
          user_row.call(bot_retyped_to_human_id, :human, minute: 1),
          user_row.call(human_retyped_to_bot_id, :human),
          user_row.call(human_retyped_to_bot_id, :service_account, minute: 1),
          *non_human_types.zip(non_human_ids).map { |type, id| user_row.call(id, type) }
        ])

        reload_non_human_users_dict
      end

      # A loaded dictionary returns rows, so the suite's truncate hook would try to TRUNCATE it and fail.
      # Emptying the source and reloading evicts them.
      after do
        ClickHouse::Client.execute('TRUNCATE TABLE siphon_users', :main)
        reload_non_human_users_dict
      end

      def reload_non_human_users_dict
        ClickHouse::Client.execute('SYSTEM RELOAD DICTIONARY non_human_users_dict', click_house_admin_database)
      end

      it 'keeps humans, including deleted or retyped-to-human users' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :author_human, values: true }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 3 }
        ])
      end

      it 'keeps every non-human user type, retyped-to-bot users, and merge requests with no author' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :author_human, values: false }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: non_human_types.size + 2 }
        ])
      end
    end

    describe 'author_id_not' do
      it 'excludes the given author Global ID' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :author_id_not, values: 'gid://gitlab/User/1' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 1 }
        ])
      end

      context 'with a merge request that has no author' do
        let(:merge_requests_data) do
          [
            { id: 1, author_id: 1,   state_id: state[:opened], target_branch: 'main', created_at: 10.days.ago },
            { id: 2, author_id: 2,   state_id: state[:opened], target_branch: 'main', created_at: 10.days.ago },
            { id: 3, author_id: nil, state_id: state[:opened], target_branch: 'main', created_at: 10.days.ago }
          ]
        end

        it 'also excludes rows where the column is NULL' do
          request = {
            metrics: [{ identifier: :total_count }],
            filters: [{ identifier: :author_id_not, values: 'gid://gitlab/User/1' }]
          }

          expect(engine).to execute_aggregation(request).and_return([
            { total_count: 1 }
          ])
        end
      end
    end

    describe 'target_branch_not' do
      it 'excludes the given target branch' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :target_branch_not, values: 'main' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 1 }
        ])
      end
    end

    describe 'state_id_not' do
      it 'excludes the given state name string' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id_not, values: 'merged' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end

      it 'returns every row when all state names are unrecognized' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :state_id_not, values: 'invalid' }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 3 }
        ])
      end
    end

    describe 'created_at' do
      it 'filters by created_at range' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :created_at, values: (30.days.ago..) }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 2 }
        ])
      end
    end

    describe 'metric_merged_at' do
      it 'filters by metric_merged_at range' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :metric_merged_at, values: (30.days.ago..) }]
        }

        expect(engine).to execute_aggregation(request).and_return([
          { total_count: 0 }
        ])
      end
    end
  end

  describe 'comprehensive test with all metrics, dimensions, and filters combined' do
    let(:merge_requests_data) do
      [
        # Pass filters: main branch, within 30 days
        { id: 1, state_id: state[:merged], target_branch: 'main', created_at: 10.days.ago,
          metric_merged_at: 10.days.ago + 100.seconds },
        { id: 2, state_id: state[:merged], target_branch: 'main', created_at: 10.days.ago,
          metric_merged_at: 10.days.ago + 200.seconds },
        # Excluded: created_at outside 30-day window
        { id: 3, state_id: state[:merged], target_branch: 'main', created_at: 50.days.ago,
          metric_merged_at: 50.days.ago + 300.seconds },
        # Excluded: different target branch
        { id: 4, state_id: state[:merged], target_branch: 'develop', created_at: 10.days.ago,
          metric_merged_at: 10.days.ago + 400.seconds }
      ]
    end

    it 'applies dimensions, metrics, and filters together' do
      request = {
        dimensions: [
          { identifier: :target_branch },
          { identifier: :metric_merged_at }
        ],
        metrics: [
          { identifier: :total_count },
          { identifier: :throughput_count }
        ],
        filters: [
          { identifier: :target_branch, values: 'main' },
          { identifier: :created_at, values: (30.days.ago..) }
        ],
        order: [
          { identifier: :target_branch,    direction: :asc },
          { identifier: :metric_merged_at, direction: :asc }
        ]
      }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        {
          target_branch: 'main',
          metric_merged_at: 10.days.ago.beginning_of_month,
          total_count: 2,
          throughput_count: 2
        }
      ]))
    end
  end
end
