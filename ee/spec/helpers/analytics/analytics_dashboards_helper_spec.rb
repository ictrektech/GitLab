# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::AnalyticsDashboardsHelper, feature_category: :product_analytics do
  let_it_be_with_refind(:group) { create(:group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate
  let_it_be_with_refind(:project) { create(:project, group: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate
  let_it_be(:user) { build_stubbed(:user) }

  before do
    allow(helper).to receive(:current_user) { user }
    allow(helper).to receive(:image_path).and_return('illustrations/empty-state/empty-dashboard-md.svg')
    allow(helper).to receive(:project_analytics_dashboards_path).with(project).and_return('/-/analytics/dashboards')
  end

  describe '#analytics_dashboards_list_app_data' do
    context 'for project' do
      subject(:data) { helper.analytics_dashboards_list_app_data(project) }

      before do
        stub_licensed_features(scoped_labels: true)
      end

      it 'returns the expected data' do
        expect(data).to eq({
          is_project: 'true',
          is_group: 'false',
          dashboard_empty_state_illustration_path: 'illustrations/empty-state/empty-dashboard-md.svg',
          namespace_full_path: project.full_path,
          router_base: '/-/analytics/dashboards',
          overview_counts_aggregation_enabled: "false",
          has_scoped_labels_feature: 'true',
          data_source_clickhouse: 'false',
          merge_request_throughput_data_source_clickhouse: 'false',
          explore_dashboards_path: '/explore/analytics_dashboards'
        })
      end

      context 'with value stream aggregation enabled' do
        before do
          create_value_stream_aggregation(project.root_ancestor)
        end

        it 'returns the expected data' do
          expect(data).to include({ overview_counts_aggregation_enabled: "true" })
        end
      end

      context 'when ClickHouse is enabled for analytics', :saas do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'returns the expected data' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "true"
          })
        end
      end

      context 'when ClickHouse is enabled for analytics on a non-SaaS instance' do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'keeps the PostgreSQL data source for merge request throughput' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "false"
          })
        end
      end
    end

    context 'for sub group' do
      let_it_be_with_refind(:sub_group) { create(:group, parent: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate

      subject(:data) { helper.analytics_dashboards_list_app_data(sub_group) }

      it 'returns the expected data' do
        expect(data).to eq({
          is_project: 'false',
          is_group: 'true',
          dashboard_empty_state_illustration_path: 'illustrations/empty-state/empty-dashboard-md.svg',
          namespace_full_path: sub_group.full_path,
          router_base: "/groups/#{sub_group.full_path}/-/analytics/dashboards",
          overview_counts_aggregation_enabled: "false",
          has_scoped_labels_feature: 'false',
          data_source_clickhouse: 'false',
          merge_request_throughput_data_source_clickhouse: 'false',
          explore_dashboards_path: '/explore/analytics_dashboards'
        })
      end

      context 'with value stream aggregation enabled' do
        before do
          create_value_stream_aggregation(sub_group.root_ancestor)
        end

        it 'returns the expected data' do
          expect(data).to include({ overview_counts_aggregation_enabled: "true" })
        end
      end

      context 'when license has scoped labels feature' do
        before do
          stub_licensed_features(scoped_labels: true)
        end

        it 'returns the expected data' do
          expect(data).to include({ has_scoped_labels_feature: "true" })
        end
      end

      context 'when ClickHouse is enabled for analytics', :saas do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'returns the expected data' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "true"
          })
        end
      end

      context 'when ClickHouse is enabled for analytics on a non-SaaS instance' do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'keeps the PostgreSQL data source for merge request throughput' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "false"
          })
        end
      end
    end

    context 'for group' do
      subject(:data) { helper.analytics_dashboards_list_app_data(group) }

      it 'returns the expected data' do
        expect(data).to eq({
          is_project: 'false',
          is_group: 'true',
          dashboard_empty_state_illustration_path: 'illustrations/empty-state/empty-dashboard-md.svg',
          namespace_full_path: group.full_path,
          router_base: "/groups/#{group.full_path}/-/analytics/dashboards",
          overview_counts_aggregation_enabled: "false",
          has_scoped_labels_feature: 'false',
          data_source_clickhouse: 'false',
          merge_request_throughput_data_source_clickhouse: 'false',
          explore_dashboards_path: '/explore/analytics_dashboards'
        })
      end

      context 'with value stream aggregation enabled' do
        before do
          create_value_stream_aggregation(group)
        end

        it 'returns the expected data' do
          expect(data).to include({ overview_counts_aggregation_enabled: "true" })
        end
      end

      context 'when license has scoped labels feature' do
        before do
          stub_licensed_features(scoped_labels: true)
        end

        it 'returns the expected data' do
          expect(data).to include({ has_scoped_labels_feature: "true" })
        end
      end

      context 'when the explore analytics dashboards flag is disabled' do
        before do
          stub_feature_flags(explore_analytics_dashboards: false)
        end

        it 'does not return a path to the explore dashboards' do
          expect(data).to include({ explore_dashboards_path: nil })
        end
      end

      context 'when ClickHouse is enabled for analytics', :saas do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'returns the expected data' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "true"
          })
        end
      end

      context 'when ClickHouse is enabled for analytics on a non-SaaS instance' do
        before do
          allow(Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
        end

        it 'keeps the PostgreSQL data source for merge request throughput' do
          expect(data).to include({
            data_source_clickhouse: "true",
            merge_request_throughput_data_source_clickhouse: "false"
          })
        end
      end
    end

    context 'when scoped labels are not licensed' do
      subject(:data) { helper.analytics_dashboards_list_app_data(project) }

      before do
        stub_licensed_features(scoped_labels: false)
      end

      it 'has_scoped_labels_feature to be false' do
        expect(data).to include({ has_scoped_labels_feature: "false" })
      end
    end
  end

  def create_value_stream_aggregation(namespace)
    create(:value_stream_dashboard_aggregation, namespace: namespace, enabled: true) # rubocop:disable RSpec/FactoryBot/AvoidCreate
  end
end
