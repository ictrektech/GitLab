# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Audit::CloseIdleSessionsWorker, :clean_gitlab_redis_shared_state,
  feature_category: :audit_events do
  subject(:worker) { described_class.new }

  describe '#perform' do
    it 'delegates to the close idle sessions service' do
      expect_next_instance_of(::Mcp::Audit::CloseIdleSessionsService) do |service|
        expect(service).to receive(:execute)
      end

      worker.perform
    end
  end

  it_behaves_like 'an idempotent worker' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }

    it 'closes a lapsed session and emits its event only once' do
      session = create(:ai_governance_session, :external,
        user: user, namespace: group, project_id: nil, source: :mcp, status: :running)
      Gitlab::Redis::SharedState.with do |redis|
        redis.zadd(::Mcp::Audit::ResolveSessionService::OPEN_SESSIONS_KEY, 1.minute.ago.to_i, session.id)
      end
      allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

      perform_idempotent_work

      expect(session.reload.status).to eq('finished')
      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async).once
    end
  end
end
