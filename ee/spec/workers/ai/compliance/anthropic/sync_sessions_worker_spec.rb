# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::SyncSessionsWorker, :freeze_time, feature_category: :ai_governance do
  let_it_be(:group) { create(:group) }
  let_it_be(:member) { create(:user, developer_of: group) }
  let_it_be_with_reload(:integration) do
    create(:ai_compliance_anthropic_integration, namespace: group, enabled: true)
  end

  let(:sessions_url) { 'https://api.anthropic.com/v1/compliance/apps/sessions/local' }
  let(:window_start) { 12.hours.ago.utc.iso8601 }
  let(:page_token) { nil }
  let(:next_page) { nil }
  let(:params) { {} }
  let(:sessions) { [claude_code_session('clls_01member', member.email)] }
  let(:expected_query) { { 'updated_at.gte' => window_start, 'limit' => '500' } }

  let!(:list_request) do
    stub_request(:get, sessions_url)
      .with(query: expected_query)
      .to_return(
        status: 200,
        body: { data: sessions, next_page: next_page }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  subject(:perform) { described_class.new.perform(integration.id, page_token, params) }

  def claude_code_session(id, email, product_surface: 'claude_code')
    {
      'type' => 'compliance_local_session',
      'id' => id,
      'product_surface' => product_surface,
      'created_at' => '2026-07-01T10:00:00Z',
      'user' => { 'id' => "user_#{id}", 'email_address' => email }
    }
  end

  it 'has the worker attributes the ingestion pipeline relies on', :aggregate_failures do
    expect(described_class.get_concurrency_limit).to eq(10)
    expect(described_class.get_urgency).to eq(:throttled)
    expect(described_class.get_sidekiq_options['retry']).to eq(0)
    expect(described_class.worker_has_external_dependencies?).to be(true)
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main,
      tables: [:ai_governance_sessions]
    )
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [integration.id, nil, {}] }

    it 'records each session once however many times it runs' do
      expect { perform_idempotent_work }.to change { Ai::Governance::Session.count }.by(1)
    end
  end

  describe '#perform' do
    it 'lists the trailing 12 hour window, one full page at a time' do
      perform

      expect(list_request).to have_been_requested.once
    end

    it 'records a session for the resolved user', :aggregate_failures do
      expect { perform }.to change { Ai::Governance::Session.count }.by(1)

      expect(Ai::Governance::Session.last).to have_attributes(
        namespace_id: group.id,
        user_id: member.id,
        external_xid: 'clls_01member',
        source: 'claude_code_compliance_api'
      )
    end

    it 'does not create a workflow row' do
      expect { perform }.not_to change { Ai::DuoWorkflows::Workflow.count }
    end

    it 'logs how the page was handled' do
      worker = described_class.new

      expect(worker).to receive(:log_hash_metadata_on_done).with(
        { sessions_listed: 1, sessions_recorded: 1, sessions_dropped: 0, sessions_skipped: 0, sessions_failed: 0 }
      )

      worker.perform(integration.id, page_token, params)
    end

    context 'when a session comes from another product surface' do
      let(:sessions) { [claude_code_session('clls_01cowork', member.email, product_surface: 'cowork')] }

      it 'skips it without resolving the user', :aggregate_failures do
        expect_next_instance_of(Ai::Compliance::Anthropic::UserResolver) do |resolver|
          expect(resolver).not_to receive(:resolve)
        end

        expect { perform }.not_to change { Ai::Governance::Session.count }
      end
    end

    context 'when the session user cannot be resolved' do
      let(:sessions) { [claude_code_session('clls_01nobody', 'nobody@example.com')] }

      it 'records nothing' do
        expect { perform }.not_to change { Ai::Governance::Session.count }
      end
    end

    context 'when recording a session fails' do
      let(:sessions) do
        [
          claude_code_session('clls_01broken', member.email).merge('created_at' => 'not a time'),
          claude_code_session('clls_01member', member.email)
        ]
      end

      it 'logs the failure and carries on with the rest of the page', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(
          hash_including(
            Labkit::Fields::LOG_MESSAGE => 'Failed to record Anthropic session',
            'reason' => :invalid_session,
            Labkit::Fields::GL_NAMESPACE_ID => group.id,
            'anthropic_session_id' => 'clls_01broken'
          )
        )

        expect { perform }.to change { Ai::Governance::Session.count }.by(1)
      end
    end

    context 'when the list has another page' do
      let(:next_page) { 'page_second' }

      it 'enqueues the next page with the same window' do
        expect(described_class).to receive(:perform_async)
          .with(integration.id, 'page_second', { 'updated_at_gte' => window_start })

        perform
      end

      it 'logs the job id of the next page' do
        worker = described_class.new
        allow(described_class).to receive(:perform_async).and_return('next_page_jid')

        expect(worker).to receive(:log_extra_metadata_on_done).with(:next_page_jid, 'next_page_jid')

        worker.perform(integration.id, page_token, params)
      end

      it 'does not mark the integration as synced' do
        expect { perform }.not_to change { integration.reload.last_successful_sync_at }
      end

      it 'does not persist the page token on the integration' do
        expect { perform }.not_to change { integration.reload.list_cursor }
      end
    end

    context 'when reading a later page of a walk' do
      let(:page_token) { 'page_second' }
      let(:params) { { 'updated_at_gte' => '2026-07-01T00:00:00Z' } }
      let(:expected_query) { { 'updated_at.gte' => '2026-07-01T00:00:00Z', 'limit' => '500', 'page' => 'page_second' } }

      it 'asks for the window the walk started with' do
        perform

        expect(list_request).to have_been_requested.once
      end

      context 'when Anthropic returns the same page token again' do
        let(:next_page) { 'page_second' }

        it 'raises instead of looping on the same page' do
          expect(described_class).not_to receive(:perform_async)

          expect { perform }.to raise_error(Ai::Compliance::Anthropic::Client::RequestError, /does not advance/)
        end
      end
    end

    context 'when the walk reaches the last page' do
      it 'marks the integration as synced and enqueues nothing', :aggregate_failures do
        expect(described_class).not_to receive(:perform_async)

        perform

        expect(integration.reload.last_successful_sync_at).to eq(Time.current)
      end
    end

    context 'when the Compliance API call fails' do
      let!(:list_request) { stub_request(:get, sessions_url).with(query: expected_query).to_return(status: 401) }

      it 'raises without marking the integration as synced', :aggregate_failures do
        expect { perform }.to raise_error(Ai::Compliance::Anthropic::Client::InvalidApiKeyError)

        expect(integration.reload.last_successful_sync_at).to be_nil
      end
    end

    shared_examples 'a walk that does not run' do
      it 'does not call the Compliance API' do
        perform

        expect(list_request).not_to have_been_requested
      end
    end

    context 'when the integration does not exist' do
      subject(:perform) { described_class.new.perform(non_existing_record_id) }

      it_behaves_like 'a walk that does not run'
    end

    context 'when the integration is disabled' do
      before do
        integration.update!(enabled: false)
      end

      it_behaves_like 'a walk that does not run'
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(claude_code_compliance_api_ingestion: false)
      end

      it_behaves_like 'a walk that does not run'
    end
  end
end
