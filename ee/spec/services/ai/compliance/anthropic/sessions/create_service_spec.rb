# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Sessions::CreateService, feature_category: :compliance_management do
  let_it_be(:integration) { create(:ai_compliance_anthropic_integration) }
  let_it_be(:user) { create(:user) }

  let(:external_xid) { 'clls_01HxKpLmNoPqRsTuVwXyZaBc' }
  let(:session_data) { { 'id' => external_xid, 'created_at' => '2026-07-01T10:00:00Z' } }

  subject(:response) { described_class.new(integration, user: user, session_data: session_data).execute }

  describe '#execute' do
    it 'creates one session row mapped from the upstream payload', :aggregate_failures do
      expect { response }.to change { Ai::Governance::Session.count }.by(1)

      expect(response).to be_success
      expect(response.payload[:session]).to have_attributes(
        namespace_id: integration.namespace_id,
        user_id: user.id,
        external_xid: external_xid,
        source: 'claude_code_compliance_api',
        status: 'finished',
        agent_type: 'claude-code',
        flow_type: 'claude_code',
        session_started_at: Time.utc(2026, 7, 1, 10),
        project_id: nil,
        workflow_id: nil,
        session_finished_at: nil
      )
    end

    it 'records an agent type Ai::ExternalAgents::AgentIdentity recognises' do
      expect(Ai::ExternalAgents::AgentIdentity::AGENT_TYPES).to include(response.payload[:session].agent_type)
    end

    context 'when the same session is ingested again' do
      # Upstream created_at moves forward as a session's oldest calls age out.
      let(:later_session_data) { { 'id' => external_xid, 'created_at' => '2026-07-02T10:00:00Z' } }

      it 'reuses the existing row and leaves session_started_at alone', :aggregate_failures do
        existing = response.payload[:session]
        repeat = nil

        expect { repeat = described_class.new(integration, user: user, session_data: later_session_data).execute }
          .not_to change { Ai::Governance::Session.count }

        expect(repeat).to be_success
        expect(repeat.payload[:session].id).to eq(existing.id)
        expect(existing.reload.session_started_at).to eq(Time.utc(2026, 7, 1, 10))
      end
    end

    context 'when a concurrent run inserts the same session first' do
      let!(:winner) do
        described_class.new(integration, user: user, session_data: session_data).execute.payload[:session]
      end

      # Hides the winning row from the lookup that guards the insert, then reveals it to the
      # re-read, which is what the losing run sees.
      def hide_then_reveal_winner
        allow(Ai::Governance::Session).to receive(:find_external).and_return(nil, winner)
      end

      it 'reads the winning row back when the uniqueness validation catches it', :aggregate_failures do
        hide_then_reveal_winner

        expect { response }.not_to change { Ai::Governance::Session.count }
        expect(response).to be_success
        expect(response.payload[:session].id).to eq(winner.id)
      end

      it 'reads the winning row back when the unique index catches it', :aggregate_failures do
        hide_then_reveal_winner
        allow(Ai::Governance::Session).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect(response).to be_success
        expect(response.payload[:session].id).to eq(winner.id)
      end

      it 'returns an error when the conflicting row cannot be read back', :aggregate_failures do
        allow(Ai::Governance::Session).to receive(:find_external).and_return(nil)
        allow(Ai::Governance::Session).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect(response).to be_error
        expect(response.reason).to eq(:session_conflict)
      end
    end

    context 'when the same session id arrives for another namespace' do
      let_it_be(:other_integration) { create(:ai_compliance_anthropic_integration) }

      it 'creates a separate row', :aggregate_failures do
        first = response.payload[:session]
        other = nil

        expect { other = described_class.new(other_integration, user: user, session_data: session_data).execute }
          .to change { Ai::Governance::Session.count }.by(1)

        expect(other.payload[:session].id).not_to eq(first.id)
        expect(other.payload[:session].namespace_id).to eq(other_integration.namespace_id)
      end
    end

    context 'when no user was resolved' do
      let(:user) { nil }

      it 'returns an error and writes nothing', :aggregate_failures do
        expect { response }.not_to change { Ai::Governance::Session.count }
        expect(response).to be_error
        expect(response.reason).to eq(:missing_user)
        expect(response.message).to eq('A resolved user is required')
      end
    end

    context 'when the upstream payload has no session id' do
      let(:session_data) { { 'created_at' => '2026-07-01T10:00:00Z' } }

      it 'returns an error and writes nothing', :aggregate_failures do
        expect { response }.not_to change { Ai::Governance::Session.count }
        expect(response).to be_error
        expect(response.reason).to eq(:missing_external_xid)
      end
    end

    context 'when the upstream created_at is unusable' do
      let(:session_data) { { 'id' => external_xid, 'created_at' => 'yesterday at noon' } }

      it 'returns an error and writes nothing', :aggregate_failures do
        expect { response }.not_to change { Ai::Governance::Session.count }
        expect(response).to be_error
        expect(response.reason).to eq(:invalid_session)
        expect(response.message).to include("Session started at can't be blank")
      end
    end
  end
end
