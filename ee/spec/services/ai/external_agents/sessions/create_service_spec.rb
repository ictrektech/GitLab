# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ExternalAgents::Sessions::CreateService, feature_category: :software_composition_analysis do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:identity) do
    create(:ai_agent_identity, user: user, project: project,
      agent_type: 'claude-code', machine_fingerprint: 'a' * 64)
  end

  let(:params) do
    {
      agent_type: 'claude-code',
      agent_identity_id: identity.id,
      sync_type: 'hook'
    }
  end

  subject(:service) { described_class.new(project: project, current_user: user, params: params) }

  before do
    allow(user).to receive(:can?).with(:create_ai_agent_session, project).and_return(true)
  end

  describe '#execute' do
    context 'when RecordNotUnique is raised and the session belongs to current user' do
      let(:params) { super().merge(idempotency_key: 'test-uuid-123') }

      before do
        service.execute
        allow_next_instance_of(Ai::Governance::Session) do |instance|
          allow(instance).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
        end
        allow(service).to receive(:find_or_build_session).and_return(
          ::Ai::Governance::Session.new
        )
      end

      it 'returns the existing session' do
        result = service.execute
        expect(result).to be_success
        expect(result.payload[:session]).to be_a(Ai::Governance::Session)
      end

      it 'does not track the session' do
        expect { service.execute }.not_to trigger_internal_events('create_external_agent_session')
      end
    end

    context 'when RecordNotUnique is raised and no idempotency key is set' do
      before do
        allow_next_instance_of(Ai::Governance::Session) do |instance|
          allow(instance).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
        end
      end

      it 'returns a conflict error' do
        result = service.execute
        expect(result).to be_error
        expect(result.message).to eq('Session already exists for this idempotency key')
      end
    end

    it 'records a sync for the agent identity' do
      expect(Ai::ExternalAgents::AgentIdentity).to receive(:record_sync).with(identity.id)

      service.execute
    end

    context 'when the session cannot be created' do
      before do
        allow_next_instance_of(Ai::Governance::Session) do |instance|
          allow(instance).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
        end
      end

      it 'does not record a sync' do
        expect(Ai::ExternalAgents::AgentIdentity).not_to receive(:record_sync)

        expect(service.execute).to be_error
      end
    end

    context 'when the agent identity does not belong to the user' do
      let(:params) { super().merge(agent_identity_id: non_existing_record_id) }

      it 'does not record a sync' do
        expect(Ai::ExternalAgents::AgentIdentity).not_to receive(:record_sync)

        expect(service.execute).to be_error
      end
    end

    context 'when glab_version and agent_version are provided' do
      let(:params) { super().merge(glab_version: 'glab 1.121.0 (abc1234)', agent_version: '2.1.295') }

      it 'stores them on the session' do
        session = service.execute.payload[:session]

        expect(session).to have_attributes(glab_version: 'glab 1.121.0 (abc1234)', agent_version: '2.1.295')
      end
    end

    context 'when no idempotency key is provided' do
      let(:params) { super().except(:idempotency_key) }

      it 'does not look up an existing session and creates a new one' do
        expect(Ai::Governance::Session).not_to receive(:find_by_external_xid)
        expect { service.execute }.to change { Ai::Governance::Session.where(source: :claude_code_glab).count }.by(1)
      end
    end

    context 'when session fails validation' do
      before do
        allow_next_instance_of(Ai::Governance::Session) do |instance|
          allow(instance).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
        end
      end

      it 'returns an error' do
        result = service.execute

        expect(result).to be_error
      end
    end

    context 'when authorized' do
      it 'creates a new session' do
        expect { service.execute }.to change { Ai::Governance::Session.where(source: :claude_code_glab).count }.by(1)
      end

      it 'returns success with the session' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:session]).to be_a(Ai::Governance::Session)
        expect(result.payload[:session].agent_type).to eq('claude-code')
        expect(result.payload[:session].source).to eq('claude_code_glab')
      end

      it 'tracks the session creation', :clean_gitlab_redis_shared_state do
        expect { service.execute }
          .to trigger_internal_events('create_external_agent_session')
          .with(user: user, project: project, additional_properties: { label: 'claude-code', property: 'hook' })
          .and increment_usage_metrics(
            'counts.count_total_create_external_agent_session',
            'redis_hll_counters.count_distinct_user_id_from_create_external_agent_session_weekly',
            'redis_hll_counters.count_distinct_project_id_from_create_external_agent_session_weekly'
          )
      end

      it 'stores the agent identity on the session' do
        result = service.execute

        expect(result.payload[:session].reload.agent_identity_id).to eq(identity.id)
      end

      it 'stores the sync type on the session' do
        result = service.execute

        expect(result.payload[:session].reload.sync_type).to eq('hook')
      end

      context 'when no agent_identity_id is passed' do
        let(:params) { super().except(:agent_identity_id) }

        it 'leaves agent_identity_id nil' do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:session].reload.agent_identity_id).to be_nil
        end
      end

      it 'transitions the session to running' do
        result = service.execute

        expect(result.payload[:session].status).to eq('running')
      end

      context 'when RecordNotUnique is raised and the colliding session belongs to another user' do
        let(:params) { super().merge(idempotency_key: 'test-uuid-123') }

        before do
          create(:ai_governance_session, :external,
            namespace: project.project_namespace,
            project: project,
            user: create(:user, developer_of: project),
            source: :claude_code_glab,
            external_xid: 'test-uuid-123')
          allow_next_instance_of(Ai::Governance::Session) do |instance|
            allow(instance).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
          end
        end

        it 'returns a conflict error' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Session already exists for this idempotency key')
        end
      end

      context 'with an idempotency key' do
        let(:params) { super().merge(idempotency_key: 'test-uuid-123') }

        it 'is idempotent -- returns existing session on repeat call' do
          first_result = service.execute
          second_result = service.execute

          expect(second_result).to be_success
          expect(second_result.payload[:session].id).to eq(first_result.payload[:session].id)
          expect(Ai::Governance::Session.where(source: :claude_code_glab, external_xid: 'test-uuid-123').count).to eq(1)
        end

        it 'does not track the session again on repeat call' do
          service.execute

          expect { service.execute }.not_to trigger_internal_events('create_external_agent_session')
        end

        it 'keeps the sync type of the call that created the session' do
          service.execute
          retry_result = described_class.new(project: project, current_user: user,
            params: params.merge(sync_type: 'fallback')).execute

          expect(retry_result.payload[:session].reload.sync_type).to eq('hook')
        end
      end

      context 'with a started_at timestamp' do
        let(:started_at) { 1.hour.ago }
        let(:params) { super().merge(started_at: started_at) }

        it 'sets session_started_at to started_at' do
          result = service.execute

          expect(result.payload[:session].session_started_at).to be_within(1.second).of(started_at)
        end
      end

      context 'when started_at is more than 30 days in the past' do
        let(:params) { super().merge(started_at: 31.days.ago) }

        it 'returns an error' do
          result = service.execute
          expect(result).to be_error
          expect(result.message).to include('30 days')
        end
      end

      context 'with a future started_at timestamp' do
        let(:params) { super().merge(started_at: 1.hour.from_now) }

        it 'returns an error' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to include('future')
        end

        it 'does not create a session' do
          expect { service.execute }.not_to change { Ai::Governance::Session.where(source: :claude_code_glab).count }
        end
      end

      context 'when agent_identity_id belongs to a different agent_type' do
        let_it_be(:opencode_identity) do
          create(:ai_agent_identity, user: user, project: project,
            agent_type: 'opencode', machine_fingerprint: 'b' * 64)
        end

        let(:params) { super().merge(agent_type: 'claude-code', agent_identity_id: opencode_identity.id) }

        it 'returns not found error' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Agent identity not found')
        end
      end

      context 'when agent_identity is revoked' do
        let_it_be(:revoked_identity) do
          create(:ai_agent_identity, user: user, project: project,
            agent_type: 'claude-code', machine_fingerprint: 'c' * 64,
            revoked_at: Time.current)
        end

        let(:params) { super().merge(agent_identity_id: revoked_identity.id) }

        it 'returns not found error' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Agent identity not found')
        end
      end
    end

    context 'when not authorized' do
      before do
        allow(user).to receive(:can?).with(:create_ai_agent_session, project).and_return(false)
      end

      it 'returns an error' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('Unauthorized')
      end

      it 'does not create a session' do
        expect { service.execute }.not_to change { Ai::Governance::Session.where(source: :claude_code_glab).count }
      end
    end
  end
end
