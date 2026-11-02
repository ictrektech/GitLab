# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ExternalAgents::Sessions::CompleteService, feature_category: :software_composition_analysis do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:other_user) { create(:user, developer_of: project) }
  let_it_be(:identity) do
    create(:ai_agent_identity, user: user, project: project,
      agent_type: 'claude-code', machine_fingerprint: 'a' * 64)
  end

  let_it_be_with_reload(:session) do
    create(:ai_governance_session, :external,
      namespace: project.project_namespace,
      project: project,
      user: user,
      source: :claude_code_glab,
      status: :running,
      agent_type: 'claude-code')
  end

  let(:params) { { status: 'completed' } }

  subject(:service) do
    described_class.new(project: project, current_user: user, session: session, params: params)
  end

  before do
    allow(user).to receive(:can?).with(:update_ai_agent_session, project).and_return(true)
  end

  describe '#execute' do
    context 'when authorized and owner' do
      it 'transitions the session to finished' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:session].status).to eq('finished')
      end

      it 'tracks the session completion', :clean_gitlab_redis_shared_state do
        expect { service.execute }
          .to trigger_internal_events('complete_external_agent_session')
          .with(user: user, project: project, additional_properties: { label: 'claude-code', property: 'finished' })
          .and increment_usage_metrics('counts.count_total_complete_external_agent_session')
      end

      it 'records a sync for the session agent identity' do
        session.update!(agent_identity: identity)

        expect(Ai::ExternalAgents::AgentIdentity).to receive(:record_sync).with(identity.id)

        service.execute
      end

      context 'when the session cannot be saved' do
        before do
          allow(session).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
        end

        it 'does not record a sync' do
          expect(Ai::ExternalAgents::AgentIdentity).not_to receive(:record_sync)

          expect(service.execute).to be_error
        end
      end

      context 'when status is failed' do
        let(:params) { { status: 'failed' } }

        it 'transitions the session to failed' do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:session].status).to eq('failed')
        end

        it 'tracks the failed status' do
          expect { service.execute }
            .to trigger_internal_events('complete_external_agent_session')
            .with(user: user, project: project, additional_properties: { label: 'claude-code', property: 'failed' })
        end
      end

      context 'when not the session owner' do
        subject(:service) do
          described_class.new(project: project, current_user: other_user, session: session, params: params)
        end

        before do
          allow(other_user).to receive(:can?).with(:update_ai_agent_session, project).and_return(true)
        end

        it 'returns a forbidden error' do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:forbidden)
        end

        it 'does not record a sync' do
          expect(Ai::ExternalAgents::AgentIdentity).not_to receive(:record_sync)

          service.execute
        end

        it 'does not change the session status' do
          expect { service.execute }.not_to change { session.reload.status }
        end
      end

      context 'when session is already terminal' do
        before do
          session.update!(status: :finished)
        end

        it 'returns success without updating the session' do
          expect { service.execute }.not_to change { session.reload.updated_at }
          expect(service.execute).to be_success
          expect(session.reload.status).to eq('finished')
        end

        it 'does not track the completion' do
          expect { service.execute }.not_to trigger_internal_events('complete_external_agent_session')
        end
      end

      context 'when another request completes the session after it was loaded' do
        let(:finished_at) { 1.minute.ago.round }

        before do
          Ai::Governance::Session.id_in(session.id)
            .update_all(status: Ai::Governance::Session.statuses[:failed], session_finished_at: finished_at)
        end

        it 'keeps the other request\'s completion and does not track it again' do
          result = nil

          expect { result = service.execute }
            .not_to trigger_internal_events('complete_external_agent_session')

          expect(result).to be_success
          expect(result.payload[:session]).to have_attributes(status: 'failed', session_finished_at: finished_at)
        end
      end
    end

    context 'when not authorized' do
      before do
        allow(user).to receive(:can?).with(:update_ai_agent_session, project).and_return(false)
      end

      it 'returns an unauthorized error' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('Unauthorized')
      end
    end
  end
end
