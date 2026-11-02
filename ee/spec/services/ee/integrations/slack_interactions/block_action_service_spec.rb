# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInteractions::BlockActionService, feature_category: :duo_agent_platform do
  describe '#execute' do
    let(:action) { { action_id: 'duo_feedback', value: 'up:1' } }
    let(:params) do
      {
        team: { id: 'T0001' },
        user: { id: 'U0001' },
        actions: [action]
      }
    end

    subject(:execute) { described_class.new(params).execute }

    it 'routes duo_feedback actions to the DuoFeedbackHandler' do
      expect_next_instance_of(
        Integrations::SlackInteractions::SlackBlockActions::DuoFeedbackHandler, params, action
      ) do |handler|
        expect(handler).to receive(:execute)
      end

      execute
    end

    %w[duo_approval_approve duo_approval_deny].each do |action_id|
      context "with a #{action_id} action" do
        let(:action) { { action_id: action_id, value: '1:aaaabbbbccccdddd' } }

        it 'routes to the DuoApprovalDecisionHandler' do
          expect_next_instance_of(
            Integrations::SlackInteractions::SlackBlockActions::DuoApprovalDecisionHandler, params, action
          ) do |handler|
            expect(handler).to receive(:execute)
          end

          execute
        end
      end
    end
  end
end
