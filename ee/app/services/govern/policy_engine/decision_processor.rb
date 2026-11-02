# frozen_string_literal: true

module Govern
  module PolicyEngine
    class DecisionProcessor
      include Gitlab::Utils::StrongMemoize

      def initialize(subject:, actor:, trigger:, act_on_policy_ids: nil)
        @subject = subject
        @actor = actor
        @trigger = trigger
        @act_on_policy_ids = act_on_policy_ids
      end

      def process(response)
        decisions = response[:decisions]
        policies = policies_for(decisions)
        evaluated_at = Time.current

        decisions.each do |decision|
          policy = policies[decision[:policy_id]]
          next log(event: 'govern_unknown_policy', policy_id: decision[:policy_id]) unless policy

          act_on(decision, policy, evaluated_at)
        end

        EvaluateService::Result.new(
          verdict: verdict(response), decisions: decisions, identifier: response[:identifier], policies: policies
        )
      end

      private

      attr_reader :subject, :actor, :trigger, :act_on_policy_ids

      # Dispatch runs first and outside the transaction: it writes audit events
      # on main and enqueues their streaming, which a Sec transaction neither
      # covers nor should hold open.
      def act_on(decision, policy, evaluated_at)
        outcomes = dispatch_actions(decision, policy)

        ::SecApplicationRecord.transaction do
          record_evaluation(decision, policy, evaluated_at)
          # Enforcement rows track stored state, which a proposed write is not.
          track_enforcement(decision, policy, evaluated_at, outcomes) unless gate_trigger?
        end
      end

      def policies_for(decisions)
        # rubocop:disable Rails/Pluck -- plain array of hashes, not a relation
        Govern::Policy.for_organization(organization_id)
          .id_in(decisions.map { |decision| decision[:policy_id] }).index_by(&:id)
        # rubocop:enable Rails/Pluck
      end

      # An undecided policy is never allow, and any gating action denies.
      # GLAZ stamps gating from the policy's enforcement mode, so an audit or
      # warn match reports its actions non-gating and never denies here.
      def verdict(response)
        return :undecidable if response[:undecided_policy_ids].any?
        return :deny if response[:decisions].any? { |d| d[:actions].any? { |a| a[:gating] } }

        :allow
      end

      def record_evaluation(decision, policy, evaluated_at)
        # TODO: record an undecided policy as undecidable once the evaluation
        # verdict enum has that value. Deny is the fail-closed stand-in.
        # https://gitlab.com/gitlab-org/gitlab/-/work_items/634766
        violated = decision[:error] || decision[:matched]

        Gitlab::PolicyStore.record_evaluation(
          organization_id: organization_id,
          policy_id: policy.id,
          policy_version: policy.version,
          trigger_type: trigger,
          mode: policy.mode,
          verdict: violated ? 'deny' : 'allow',
          evaluated_at: evaluated_at,
          project_id: subject.id,
          user_id: actor.id,
          violations: violations_for(decision)
        )
      end

      def violations_for(decision)
        ViolationDetails.from_decision(decision).to_a.map { |detail| { 'details' => detail } }
      end

      # TODO: take the enforcement mode from the decision once the engine
      # reports it. Until then it comes from the local policy row.
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/634767
      def dispatch_actions(decision, policy)
        return [] unless decision[:matched] && decision[:error].nil?
        return [] if act_on_policy_ids&.exclude?(policy.id)

        decision[:actions].filter_map do |action|
          action_type = action[:action_type]

          unless ActionCatalog.known?(action_type)
            log(event: 'govern_unhandled_action', action_type: action_type, policy_id: policy.id)
            next
          end

          executor = ActionCatalog.executor_for(action_type, enforce: policy.mode_enforce?)
          next unless executor

          dispatch(executor, action, decision, policy)
        end
      end

      def dispatch(executor, action, decision, policy)
        outcome = executor.constantize.new(
          subject: subject, policy: policy, decision: decision, action: action, actor: actor
        ).execute

        log(event: 'govern_action_dispatched', action_type: action[:action_type], policy_id: policy.id, **outcome)

        outcome
      end

      def track_enforcement(decision, policy, evaluated_at, outcomes)
        # rubocop:disable CodeReuse/ActiveRecord -- this service is the prototype enforcement write seam
        enforcement = Govern::PolicyEnforcement.find_or_initialize_by(
          organization_id: organization_id, govern_policy_id: policy.id, project_id: subject.id
        )
        # rubocop:enable CodeReuse/ActiveRecord

        enforcement.state = EnforcementState.for(decision: decision, policy: policy, outcomes: outcomes)
        enforcement.last_evaluated_at = evaluated_at
        enforcement.save!
      end

      # A gate trigger evaluates a proposed change that may never commit.
      # GOVERN-016: filtering on triggers uses the kind, never the name.
      def gate_trigger?
        ::Gitlab::PolicyStore::Triggers.gate?(trigger)
      end
      strong_memoize_attr :gate_trigger?

      def organization_id
        subject.organization_id
      end

      def log(payload)
        Gitlab::AppJsonLogger.info(
          feature_category: :security_policy_management,
          subject_kind: :project,
          subject_id: subject.id,
          trigger: trigger,
          **payload
        )
      end
    end
  end
end
