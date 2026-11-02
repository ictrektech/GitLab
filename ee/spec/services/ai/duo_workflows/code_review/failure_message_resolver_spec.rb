# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::FailureMessageResolver, feature_category: :duo_agent_platform do
  let_it_be(:user) { build_stubbed(:user) }
  let_it_be(:project) { build_stubbed(:project) }

  subject(:resolver) { described_class.new(user: user, project: project) }

  describe '#resolve' do
    context 'with known failure reasons' do
      where(:reason, :expected_message) do
        [
          [:flow_not_enabled,           -> { ::Gitlab::Duo::CodeReview::Messages.foundational_flow_not_enabled_error }],
          [:invalid_service_account,    -> { ::Gitlab::Duo::CodeReview::Messages.missing_service_account_error }],
          [:service_account_error,      -> { ::Gitlab::Duo::CodeReview::Messages.missing_service_account_error }],
          [:usage_quota_exceeded,       -> { ::Gitlab::Duo::CodeReview::Messages.usage_quota_exceeded_error }],
          [:usage_billing_forbidden,    -> { ::Gitlab::Duo::CodeReview::Messages.usage_billing_forbidden_error }],
          [:namespace_missing,          -> { ::Gitlab::Duo::CodeReview::Messages.namespace_missing_error(user) }],
          [
            :cannot_create_workflow_pipeline,
            -> { ::Gitlab::Duo::CodeReview::Messages.insufficient_workload_permissions_error(user) }
          ],
          [:workload_failure,           -> { ::Gitlab::Duo::CodeReview::Messages.workload_creation_error }],
          [:workflow_workload_failure,  -> { ::Gitlab::Duo::CodeReview::Messages.workload_creation_error }],
          [:feature_unavailable,        -> { ::Gitlab::Duo::CodeReview::Messages.feature_unavailable_error }],
          [:invalid_duo_workflow_token, -> { ::Gitlab::Duo::CodeReview::Messages.invalid_token_error }],
          [:invalid_oauth_token,        -> { ::Gitlab::Duo::CodeReview::Messages.invalid_token_error }],
          [:source_ref_not_found,       -> { ::Gitlab::Duo::CodeReview::Messages.source_ref_not_found_error }],
          [
            :no_eligible_runner,
            -> {
              ::Gitlab::Duo::CodeReview::Messages.no_eligible_runner_error(
                tag: ::Ai::DuoWorkflows::Workflow::SUSPENDABLE_WORKLOAD_TAG
              )
            }
          ],
          [
            :namespace_ci_minutes_used_up,
            -> { ::Gitlab::Duo::CodeReview::Messages.namespace_ci_minutes_used_up_error }
          ],
          [:trigger_depth_exceeded,      -> { ::Gitlab::Duo::CodeReview::Messages.flow_chain_limit_error }],
          [:trigger_breadth_exceeded,    -> { ::Gitlab::Duo::CodeReview::Messages.flow_chain_limit_error }],
          [:trigger_chain_size_exceeded, -> { ::Gitlab::Duo::CodeReview::Messages.flow_chain_limit_error }],
          [:chain_root_not_human,        -> { ::Gitlab::Duo::CodeReview::Messages.flow_chain_limit_error }],
          [
            :parent_workflow_namespace_mismatch,
            -> { ::Gitlab::Duo::CodeReview::Messages.flow_chain_limit_error }
          ]
        ]
      end

      with_them do
        it "resolves :#{params[:reason]}" do
          expect(resolver.resolve(reason)).to eq(instance_exec(&expected_message))
        end
      end
    end

    context 'with :no_eligible_runner when suspendable_workload_tag_for_dap is disabled' do
      before do
        stub_feature_flags(suspendable_workload_tag_for_dap: false)
      end

      it 'names the default workload tag' do
        expect(resolver.resolve(:no_eligible_runner)).to include('`gitlab--duo`')
      end
    end

    context 'with an unknown failure reason' do
      it 'returns the default could not start workflow error' do
        expect(resolver.resolve(:some_unknown_reason))
          .to eq(::Gitlab::Duo::CodeReview::Messages.could_not_start_workflow_error)
      end
    end
  end

  describe '#known_reason?' do
    it 'returns true for known reasons' do
      described_class::KNOWN_FAILURE_MESSAGES.each_key do |reason|
        expect(resolver.known_reason?(reason)).to be(true), "expected #{reason} to be a known reason"
      end
    end

    it 'returns false for unknown reasons' do
      expect(resolver.known_reason?(:some_unknown_reason)).to be(false)
    end
  end
end
