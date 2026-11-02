# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin::DatabaseDiagnostics', feature_category: :database do
  include AdminModeHelper

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  shared_examples 'unauthorized request' do
    context 'when user is not an admin' do
      before do
        login_as(user)
      end

      it 'returns 404 response' do
        send_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when admin mode is disabled' do
      before do
        login_as(admin)
      end

      it 'redirects to admin mode enable' do
        send_request

        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  describe 'GET /admin/database_diagnostics' do
    subject(:send_request) do
      get admin_database_diagnostics_path
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      it 'returns 200 response' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'triggers an internal event and increments the unique user metric', :clean_gitlab_redis_shared_state do
        expect { send_request }
          .to trigger_internal_events('visit_db_diagnostics_page')
          .with(user: admin, category: 'Admin::DatabaseDiagnosticsController')
          .and increment_usage_metrics(
            'redis_hll_counters.count_distinct_user_id_from_visit_db_diagnostics_page_monthly',
            'redis_hll_counters.count_distinct_user_id_from_visit_db_diagnostics_page_weekly'
          )
      end

      it 'embeds database information as a data attribute', :aggregate_failures do
        information_payload = {
          databases: { 'main' => { search_path: '"$user", public', schemas: [] } }
        }

        expect(::Gitlab::Database::DatabaseInformation).to receive(:execute).and_return(information_payload)

        send_request

        expect(response.body).to include('data-database-information')
        expect(response.body).to include('&quot;search_path&quot;:&quot;\&quot;$user\&quot;, public&quot;')
      end
    end
  end

  describe 'POST /admin/database_diagnostics/run_collation_check' do
    subject(:send_request) do
      post run_collation_check_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      it 'returns 200 response and schedules the worker' do
        expect(::Database::CollationCheckerWorker).to receive(:perform_async).and_return('job_id')

        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('status' => 'scheduled', 'job_id' => 'job_id')
      end

      it 'returns 500 response when worker fails to schedule' do
        expect(::Database::CollationCheckerWorker).to receive(:perform_async).and_return(nil)

        send_request

        expect(response).to have_gitlab_http_status(:internal_server_error)
        expect(json_response).to include('error' => 'Failed to schedule job')
      end
    end
  end

  describe 'POST /admin/database_diagnostics/run_schema_check' do
    subject(:send_request) do
      post run_schema_check_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      it 'returns 200 response and schedules the worker' do
        expect(::Database::SchemaCheckerWorker).to receive(:perform_async).and_return('schema_job_id')

        send_request
        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('status' => 'scheduled', 'job_id' => 'schema_job_id')
      end

      it 'returns 500 response when worker fails to schedule' do
        expect(::Database::SchemaCheckerWorker).to receive(:perform_async).and_return(nil)

        send_request

        expect(response).to have_gitlab_http_status(:internal_server_error)
        expect(json_response).to include('error' => 'Failed to schedule job')
      end
    end
  end

  describe 'POST /admin/database_diagnostics/run_lfk_backlog_check' do
    subject(:send_request) do
      post run_lfk_backlog_check_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      it 'returns 200 response and schedules the worker' do
        expect(::Database::LooseForeignKeysBacklogCheckerWorker).to receive(:perform_async).and_return('lfk_job_id')

        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('status' => 'scheduled', 'job_id' => 'lfk_job_id')
      end

      it 'returns 500 response when worker fails to schedule' do
        expect(::Database::LooseForeignKeysBacklogCheckerWorker).to receive(:perform_async).and_return(nil)

        send_request

        expect(response).to have_gitlab_http_status(:internal_server_error)
        expect(json_response).to include('error' => 'Failed to schedule job')
      end
    end
  end

  describe 'GET /admin/database_diagnostics/lfk_backlog_check_results' do
    subject(:send_request) do
      get lfk_backlog_check_results_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      context 'when results are available' do
        let(:results) do
          {
            metadata: { last_run_at: Time.current.iso8601 },
            connections: {
              main: [
                {
                  parent_table: 'public.projects',
                  pending_records: 49_459,
                  capped: false,
                  oldest_pending_age_seconds: 50_000_000,
                  deferred_records: 0
                }
              ]
            }
          }
        end

        it 'returns 200 response with the results' do
          allow(Rails.cache).to receive(:read)
          expect(Rails.cache).to receive(:read)
            .with(::Database::LooseForeignKeysBacklogCheckerWorker::BACKLOG_CHECK_CACHE_KEY)
            .and_return(results.to_json)

          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('metadata', 'connections')
        end
      end

      context 'when no results are available' do
        it 'returns 404 response' do
          send_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response).to include('error' => 'No results available yet')
        end
      end
    end
  end

  describe 'GET /admin/database_diagnostics/collation_check_results' do
    subject(:send_request) do
      get collation_check_results_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      context 'when results are available' do
        let(:results) do
          {
            metadata: { last_run_at: Time.current.iso8601 },
            databases: {
              main: {
                collation_mismatches: [],
                corrupted_indexes: []
              }
            }
          }
        end

        it 'returns 200 response with the results' do
          allow(Rails.cache).to receive(:read)
          expect(Rails.cache).to receive(:read)
            .with(::Database::CollationCheckerWorker::COLLATION_CHECK_CACHE_KEY)
            .and_return(results.to_json)

          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('metadata', 'databases')
        end
      end

      context 'when no results are available' do
        it 'returns 404 response' do
          send_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response).to include('error' => 'No results available yet')
        end
      end
    end
  end

  describe 'GET /admin/database_diagnostics/schema_check_results' do
    subject(:send_request) do
      get schema_check_results_admin_database_diagnostics_path(format: :json)
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      context 'when results are available' do
        let(:results) do
          {
            metadata: { last_run_at: Time.current.iso8601 },
            schema_check_results: {
              main: {
                missing_indexes: []
              }
            }
          }
        end

        it 'returns 200 response with the results' do
          allow(Rails.cache).to receive(:read)
          expect(Rails.cache).to receive(:read)
            .with(::Database::SchemaCheckerWorker::SCHEMA_CHECK_CACHE_KEY)
            .and_return(results.to_json)

          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('schema_check_results', 'metadata')
        end
      end

      context 'when no results are available' do
        it 'returns 404 response' do
          send_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response).to include('error' => 'No results available yet')
        end
      end
    end
  end

  shared_context 'with pg_ash installed' do
    let(:installed_version) { Gitlab::Database::PgAsh::VENDORED_VERSION }
    let(:report) { instance_double(Gitlab::Database::PgAsh::Report) }
    # At 10:00:42 the default windows end a minute back, at 09:59.
    let(:overview_window) { Time.utc(2026, 10, 15, 8, 58)..Time.utc(2026, 10, 15, 9, 59) }
    let(:overview_window_json) { { 'from' => '2026-10-15T08:58:00Z', 'to' => '2026-10-15T09:59:00Z' } }
    let(:drill_down_window) { Time.utc(2026, 10, 15, 9, 54)..Time.utc(2026, 10, 15, 9, 59) }
    let(:drill_down_window_json) { { 'from' => '2026-10-15T09:54:00Z', 'to' => '2026-10-15T09:59:00Z' } }

    before do
      allow_next_instance_of(Gitlab::Database::PgAsh::Installer) do |installer|
        allow(installer).to receive(:installed_version).and_return(installed_version)
      end
      allow(Gitlab::Database::PgAsh::Report).to receive_messages(new: report, rollup_watermark: nil)
    end
  end

  shared_examples 'an anonymous active session history request' do
    it 'hides the endpoint without reading, as the admin area does' do
      expect(Gitlab::Database::PgAsh::Report).not_to receive(:new)

      send_request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'an active session history read' do |action|
    context 'when pg_ash is not installed' do
      let(:installed_version) { nil }

      it 'reports it without reading' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq('installed' => false)
        expect(Gitlab::Database::PgAsh::Report).not_to have_received(:rollup_watermark)
        expect(Gitlab::Database::PgAsh::Report).not_to have_received(:new)
      end
    end

    context 'when another pg_ash version is installed' do
      let(:installed_version) { '1.5' }

      it 'reports both versions without reading' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq('installed' => true, 'supported' => false, 'installed_version' => '1.5',
          'supported_version' => Gitlab::Database::PgAsh::VENDORED_VERSION)
        expect(Gitlab::Database::PgAsh::Report).not_to have_received(:rollup_watermark)
        expect(Gitlab::Database::PgAsh::Report).not_to have_received(:new)
      end
    end

    it 'rejects an invalid window without reading' do
      get request_path, params: request_params.merge(from: '2026-10-15T09:00:00Z', to: 'yesterday')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response).to eq('error' => 'Invalid window')
      expect(Gitlab::Database::PgAsh::Report).not_to have_received(:new)
    end

    it 'tracks a database error and returns a generic message' do
      error = ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout')
      allow(report).to receive(read_method).and_raise(error)
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(error, action: action, wait_event_type: request_params[:wait_event_type])

      send_request

      expect(response).to have_gitlab_http_status(:internal_server_error)
      expect(json_response).to eq('error' => 'Failed to read active session history')
    end
  end

  describe 'GET /admin/database_diagnostics/active_session_history', :aggregate_failures do
    subject(:send_request) { get request_path, params: request_params }

    let(:request_path) { active_session_history_admin_database_diagnostics_path(format: :json) }
    let(:request_params) { {} }

    it_behaves_like 'unauthorized request'
    it_behaves_like 'an anonymous active session history request'

    context 'when admin mode is enabled', :enable_admin_mode do
      include_context 'with pg_ash installed'

      let(:read_method) { :overview }
      let(:overview) do
        {
          coverage: { from: '2026-10-15T08:58:00Z', to: '2026-10-15T09:59:00Z', source: 'rollup_1m' },
          wait_event_types: [{ wait_event_type: 'Lock', avg_aas: 0.04, peak_aas: 2.4, p99_aas: 2.23, pct: 40.11 }],
          top_queries: [{ query_id: '-7134873239275742000', query_text: 'select 1', avg_aas: 0.04, peak_aas: 2.4,
                          p99_aas: nil, pct: 55.5 }]
        }
      end

      before do
        login_as(admin)
        allow(report).to receive(:overview).and_return(overview)
      end

      it 'returns the overview for the default window' do
        stub_application_setting(pg_ash_sampling_enabled: true)

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) { send_request }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq(
          'installed' => true,
          'window' => overview_window_json,
          'sampling_enabled' => true,
          **overview.deep_stringify_keys
        )
        expect(Gitlab::Database::PgAsh::Report).to have_received(:new).with(eq(overview_window))
      end

      it 'ends the default window at the end of the minute rollups when they lag' do
        # PostgreSQL returns times with a +00:00 offset rather than as UTC.
        allow(Gitlab::Database::PgAsh::Report).to receive(:rollup_watermark)
          .and_return(Time.new(2026, 10, 15, 9, 40, 0, '+00:00'))

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) { send_request }

        expect(json_response['window']).to eq('from' => '2026-10-15T08:39:00Z', 'to' => '2026-10-15T09:40:00Z')
      end

      it 'ends a chosen window that reaches the present at the end of the minute rollups' do
        allow(Gitlab::Database::PgAsh::Report).to receive(:rollup_watermark).and_return(Time.utc(2026, 10, 15, 9, 40))

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) do
          get request_path, params: { from: '2026-10-15T04:00:42Z', to: '2026-10-15T10:00:42Z' }
        end

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['window']).to eq('from' => '2026-10-15T04:00:00Z', 'to' => '2026-10-15T09:40:00Z')
      end

      it 'returns the newest data when the rollups ended before the chosen window started' do
        allow(Gitlab::Database::PgAsh::Report).to receive(:rollup_watermark).and_return(Time.utc(2026, 10, 15, 7, 0))

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) do
          get request_path, params: { from: '2026-10-15T09:00:42Z', to: '2026-10-15T10:00:42Z' }
        end

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['window']).to eq('from' => '2026-10-15T05:59:00Z', 'to' => '2026-10-15T07:00:00Z')
      end

      it 'still returns collected data when sampling is off' do
        stub_application_setting(pg_ash_sampling_enabled: false)

        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('sampling_enabled' => false, 'wait_event_types' => [hash_including(
          'wait_event_type' => 'Lock'
        )])
      end

      it_behaves_like 'an active session history read', 'active_session_history'
    end
  end

  describe 'GET /admin/database_diagnostics/active_session_history_queries', :aggregate_failures do
    subject(:send_request) { get request_path, params: request_params }

    let(:request_path) { active_session_history_queries_admin_database_diagnostics_path(format: :json) }
    let(:request_params) { { wait_event_type: wait_event_type } }
    let(:wait_event_type) { 'Lock' }

    it_behaves_like 'unauthorized request'
    it_behaves_like 'an anonymous active session history request'

    context 'when admin mode is enabled', :enable_admin_mode do
      include_context 'with pg_ash installed'

      let(:read_method) { :queries }
      let(:queries) do
        [{ query_id: '-7134873239275742000', query_text: 'select 1', avg_aas: 0.04, peak_aas: 2.4, p99_aas: 2.23,
           pct: 100.0 }]
      end

      before do
        login_as(admin)
        allow(report).to receive(:queries).with(wait_event_type: 'Lock').and_return(queries)
      end

      it 'returns the queries behind the wait event type, reading raw samples up to a minute back' do
        # Raw samples are newer than the rollups, so the newest rollup does not end the window.
        allow(Gitlab::Database::PgAsh::Report).to receive(:rollup_watermark).and_return(Time.utc(2026, 10, 15, 9, 40))

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) { send_request }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq(
          'installed' => true,
          'window' => drill_down_window_json,
          'queries_available' => true,
          'queries' => queries.map(&:stringify_keys)
        )
      end

      it 'reads a slice of an old window when the newest rollup is over 30 days old' do
        allow(Gitlab::Database::PgAsh::Report).to receive(:rollup_watermark).and_return(Time.utc(2026, 9, 1, 12, 0))

        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) do
          get request_path, params: request_params.merge(from: '2026-09-01T11:30:00Z', to: '2026-09-01T11:35:00Z')
        end

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['window']).to eq('from' => '2026-09-01T11:30:00Z', 'to' => '2026-09-01T11:35:00Z')
      end

      it 'reads a slice of the window the summary returned, even after minutes have passed' do
        allow(report).to receive(:overview).and_return({})

        travel_to(Time.utc(2026, 10, 15, 10, 0, 59)) do
          get active_session_history_admin_database_diagnostics_path(format: :json)
        end
        summary_end = json_response.dig('window', 'to')

        travel_to(Time.utc(2026, 10, 15, 10, 12, 1)) do
          get request_path, params: request_params.merge(from: '2026-10-15T09:54:00Z', to: summary_end)
        end

        expect(json_response.fetch('window')).to eq(drill_down_window_json)
        expect(Gitlab::Database::PgAsh::Report).to have_received(:new).with(eq(overview_window)).ordered
        expect(Gitlab::Database::PgAsh::Report).to have_received(:new).with(eq(drill_down_window)).ordered
      end

      it 'rejects a drill-down window over 5 minutes' do
        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) do
          get request_path, params: request_params.merge(from: '2026-10-15T09:53:00Z', to: '2026-10-15T09:59:00Z')
        end

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error' => 'Invalid window')
      end

      it 'reports when raw samples no longer cover the window' do
        allow(report).to receive(:queries)
          .and_raise(Gitlab::Database::PgAsh::Report::QueryDetailsUnavailableError)

        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('installed' => true, 'queries_available' => false, 'queries' => [])
      end

      context 'with a wait event type at the length limit' do
        let(:wait_event_type) { 'a' * 64 }

        it 'reads the queries' do
          allow(report).to receive(:queries).with(wait_event_type: wait_event_type).and_return([])

          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('installed' => true, 'queries' => [])
        end
      end

      context 'with an invalid wait event type' do
        using RSpec::Parameterized::TableSyntax

        where(:case_name, :wait_event_type) do
          'missing'  | nil
          'blank'    | ''
          'too long' | ('a' * 65)
          'an array' | ['Lock']
        end

        with_them do
          it 'returns 400 without reading' do
            send_request

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response).to eq('error' => 'Invalid wait event type')
            expect(Gitlab::Database::PgAsh::Report).not_to have_received(:new)
          end
        end
      end

      it_behaves_like 'an active session history read', 'active_session_history_queries'
    end
  end

  describe 'GET /admin/database_diagnostics/active_session_history_timeline', :aggregate_failures do
    subject(:send_request) { get request_path, params: request_params }

    let(:request_path) { active_session_history_timeline_admin_database_diagnostics_path(format: :json) }
    let(:request_params) { {} }

    it_behaves_like 'unauthorized request'
    it_behaves_like 'an anonymous active session history request'

    context 'when admin mode is enabled', :enable_admin_mode do
      include_context 'with pg_ash installed'

      let(:read_method) { :timeline }
      let(:timeline) do
        [{ bucket_start: '2026-10-15T09:59:00Z', source: 'rollup_1m', avg_aas: nil, peak_aas: nil, p99_aas: nil }]
      end

      before do
        login_as(admin)
        allow(report).to receive(:timeline).and_return(timeline)
      end

      it 'returns the timeline of all wait event types for the default overview window' do
        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) { send_request }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq(
          'installed' => true,
          'window' => overview_window_json,
          'timeline' => timeline.map(&:stringify_keys)
        )
        expect(report).to have_received(:timeline).with(wait_event_type: nil)
      end

      context 'with a wait event type' do
        let(:request_params) { { wait_event_type: 'Lock' } }

        it 'returns the timeline of that wait event type' do
          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('timeline' => timeline.map(&:stringify_keys))
          expect(report).to have_received(:timeline).with(wait_event_type: 'Lock')
        end
      end

      context 'with an invalid wait event type' do
        using RSpec::Parameterized::TableSyntax

        where(:case_name, :wait_event_type) do
          'blank'    | ''
          'too long' | ('a' * 65)
        end

        with_them do
          let(:request_params) { { wait_event_type: wait_event_type } }

          it 'returns 400 without reading' do
            send_request

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response).to eq('error' => 'Invalid wait event type')
            expect(Gitlab::Database::PgAsh::Report).not_to have_received(:new)
          end
        end
      end

      it 'accepts a window of up to 24 hours' do
        travel_to(Time.utc(2026, 10, 15, 10, 0, 42)) do
          get request_path, params: { from: '2026-10-14T09:59:00Z', to: '2026-10-15T09:59:00Z' }
        end

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::Database::PgAsh::Report).to have_received(:new)
          .with(eq(Time.utc(2026, 10, 14, 9, 59)..Time.utc(2026, 10, 15, 9, 59)))
      end

      it_behaves_like 'an active session history read', 'active_session_history_timeline'
    end
  end
end
