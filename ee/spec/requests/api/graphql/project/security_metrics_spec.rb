# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Security metrics through ProjectQuery', :elastic_delete_by_query, :sidekiq_inline, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:remediated_week) { Time.current.utc.beginning_of_week(:monday) - 1.week }

  let_it_be(:vulnerability) do
    create(:vulnerability, :with_finding, :resolved, severity: :critical, report_type: :sast, project: project,
      detected_at: remediated_week - 2.days, resolved_at: remediated_week + 1.day)
  end

  let(:query) do
    graphql_query_for('project', { 'fullPath' => project.full_path }, <<~FIELDS)
      securityMetrics {
        __typename
        mttrOverTime(startDate: "#{remediated_week.to_date.iso8601}", endDate: "#{Date.current.iso8601}") {
          startDate endDate count sumDays mttr
          bySeverity { severity count sumDays mttr }
          byReportType { reportType count sumDays mttr }
        }
      }
    FIELDS
  end

  let(:security_metrics_data) { graphql_data_at(:project, :security_metrics) }
  let(:mttr_over_time_data) { security_metrics_data['mttrOverTime'] }

  before do
    stub_licensed_features(security_dashboard: true)
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    Elastic::ProcessBookkeepingService.track!(vulnerability)
    ensure_elasticsearch_index!
  end

  describe 'mttrOverTime' do
    let(:mttr_chart_enabled) { true }

    before do
      stub_feature_flags(security_dashboard_mttr_chart: mttr_chart_enabled)
      post_graphql(query, current_user: current_user)
    end

    it_behaves_like 'a working graphql query'

    it_behaves_like 'a dense mttrOverTime response'

    context 'when the security_dashboard_mttr_chart feature flag is disabled' do
      let(:mttr_chart_enabled) { false }

      it 'returns null for mttrOverTime and keeps the rest of securityMetrics' do
        expect(graphql_errors).to be_nil
        expect(security_metrics_data).to eq('__typename' => 'SecurityMetrics', 'mttrOverTime' => nil)
      end
    end
  end
end
