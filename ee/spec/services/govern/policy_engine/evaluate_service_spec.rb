# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::EvaluateService, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:actor) { create(:user) }

  let(:organization) { project.organization }
  let(:policy) do
    create(:govern_policy, :without_namespace, organization: organization,
      trigger_type: 'project.after_create', mode: :enforce)
  end

  let(:engine) { instance_double(Gitlab::Glaz::GovernPolicyEngine) }
  let(:identifier) { SecureRandom.uuid }
  let(:trigger) { 'project.after_create' }

  subject(:service) { described_class.new(subject: project, actor: actor, trigger: trigger) }

  before do
    allow(Gitlab::Glaz).to receive(:govern_policy_engine).and_return(engine)
    allow(engine).to receive(:evaluate).and_return(response)
  end

  def decision(overrides = {})
    {
      policy_id: policy.id,
      matched: true,
      actions: [{ action_type: 'log_audit_trail', message: nil, params: {}, gating: false }],
      reasons: [{ message: 'drift', details: { 'path' => 'request_access_enabled', 'expected' => false,
                                               'actual' => true } }],
      error: nil
    }.merge(overrides)
  end

  def response_with(decisions:, undecided: [])
    { decisions: decisions, undecided_policy_ids: undecided, identifier: identifier }
  end

  describe 'argument validation' do
    let(:response) { response_with(decisions: []) }

    it 'refuses a trigger outside the persisted vocabulary' do
      expect { described_class.new(subject: project, actor: actor, trigger: 'sometimes') }
        .to raise_error(ArgumentError, /unknown trigger/)
    end

    it 'refuses a missing trigger' do
      expect { described_class.new(subject: project, actor: actor, trigger: nil) }
        .to raise_error(ArgumentError, /unknown trigger/)
    end

    it 'refuses a group subject: the group half left with the three-trigger model' do
      expect { described_class.new(subject: group, actor: actor, trigger: 'project.after_create') }
        .to raise_error(ArgumentError, /subject must be a Project/)
    end
  end

  describe '.engine' do
    let(:response) { response_with(decisions: []) }

    before do
      described_class.instance_variable_set(:@engine, nil)
    end

    after do
      described_class.instance_variable_set(:@engine, nil)
    end

    it 'builds one configured engine when a store URL is set', :aggregate_failures do
      configured = instance_double(Gitlab::Glaz::GovernPolicyEngine)
      allow(Gitlab::Glaz::GovernPolicyEngine).to receive(:policy_store_url).and_return('http://store.test')
      allow(Gitlab::Glaz::GovernPolicyEngine).to receive(:new)
        .with(store_base_url: 'http://store.test',
          connect_timeout_ms: described_class::LOOKUP_CONNECT_TIMEOUT_MS,
          timeout_ms: described_class::LOOKUP_TIMEOUT_MS)
        .and_return(configured)

      expect(described_class.engine).to eq(configured)
      expect(described_class.engine).to eq(configured)
      expect(Gitlab::Glaz::GovernPolicyEngine).to have_received(:new).once
    end

    it 'falls back to the shared engine without memoizing when no URL is set', :aggregate_failures do
      allow(Gitlab::Glaz::GovernPolicyEngine).to receive(:policy_store_url).and_return(nil)

      expect(described_class.engine).to eq(engine)
      expect(described_class.instance_variable_get(:@engine)).to be_nil
    end
  end

  describe 'the store credential' do
    let(:response) { response_with(decisions: []) }

    it 'passes the environment token through, and nil when it is blank', :aggregate_failures do
      stub_env('GLAZ_POLICY_STORE_TOKEN', 'Bearer abc123')
      service.execute

      expect(engine).to have_received(:evaluate).with(hash_including(store_authorization: 'Bearer abc123'))

      stub_env('GLAZ_POLICY_STORE_TOKEN', '')
      described_class.new(subject: project, actor: actor, trigger: trigger).execute

      expect(engine).to have_received(:evaluate).with(hash_including(store_authorization: nil))
    end
  end

  describe 'the trigger pass-through' do
    let(:response) { response_with(decisions: []) }

    it 'evaluates each settings trigger as given, the engine-internal one included', :aggregate_failures do
      ['project.before_settings_update', 'project.after_create', 'project.after_transfer',
        'project.scheduled_settings_drift_check'].each do |trigger|
        described_class.new(subject: project, actor: actor, trigger: trigger).execute

        expect(engine).to have_received(:evaluate)
          .with(hash_including(trigger: trigger))
      end
    end
  end

  context 'when no policy applies' do
    let(:response) { response_with(decisions: []) }

    it 'allows and records nothing', :aggregate_failures do
      result = service.execute

      expect(result.verdict).to eq(:allow)
      expect(result.identifier).to eq(identifier)
      expect(Govern::PolicyEvaluation.count).to eq(0)
    end
  end

  context 'when a policy matches in enforce mode at the create point' do
    let(:response) { response_with(decisions: [decision]) }

    it 'records the evaluation with its violation', :aggregate_failures do
      expect { service.execute }.to change { Govern::PolicyEvaluation.count }.by(1)
        .and change { Govern::PolicyViolation.count }.by(1)

      evaluation = Govern::PolicyEvaluation.last
      expect(evaluation).to have_attributes(
        trigger_type: 'project.after_create', mode: 'enforce', verdict: 'deny', project_id: project.id,
        user_id: actor.id
      )
      expect(evaluation.violations.sole.details).to include(
        'path' => 'request_access_enabled', 'expected' => false, 'message' => 'drift'
      )
    end

    it 'dispatches the matched action and tracks the enforcement' do
      executor = instance_double(Govern::PolicyEngine::LogAuditTrailExecutor,
        execute: { outcome: :audit_logged, setting: 'request_access_enabled', note: 'recorded' })
      allow(Govern::PolicyEngine::LogAuditTrailExecutor).to receive(:new).and_return(executor)

      service.execute

      expect(executor).to have_received(:execute)
      expect(Govern::PolicyEnforcement.sole).to have_attributes(
        govern_policy_id: policy.id, project_id: project.id, state: 'active'
      )
    end

    it 'does not dispatch when act_on_policy_ids excludes the policy', :aggregate_failures do
      expect(Govern::PolicyEngine::LogAuditTrailExecutor).not_to receive(:new)

      described_class.new(subject: project, actor: actor, trigger: 'project.after_create',
        act_on_policy_ids: [non_existing_record_id]).execute

      expect(Govern::PolicyEnforcement.sole.state).to eq('active')
    end

    context 'with an action type the catalog does not know yet' do
      let(:response) do
        response_with(decisions: [decision(actions: [
          { action_type: 'set_setting', message: nil, params: {}, gating: false }
        ])])
      end

      it 'records the decision and reports the action as unhandled' do
        allow(Gitlab::AppJsonLogger).to receive(:info)

        expect { service.execute }.to change { Govern::PolicyEvaluation.count }.by(1)

        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(a_hash_including(event: 'govern_unhandled_action', action_type: 'set_setting'))
        expect(Govern::PolicyEnforcement.sole.state).to eq('active')
      end
    end

    context 'when firing on the transfer trigger' do
      let(:trigger) { 'project.after_transfer' }

      it 'records the transferred trigger' do
        service.execute

        expect(Govern::PolicyEvaluation.sole.trigger_type).to eq('project.after_transfer')
      end
    end
  end

  context 'when a policy complies' do
    let(:response) { response_with(decisions: [decision(matched: false, actions: [], reasons: [])]) }

    it 'records an allow evaluation without violations and completes the enforcement', :aggregate_failures do
      service.execute

      evaluation = Govern::PolicyEvaluation.sole
      expect(evaluation.verdict).to eq('allow')
      expect(evaluation.violations).to be_empty
      expect(Govern::PolicyEnforcement.sole.state).to eq('completed')
    end
  end

  context 'when a decision names a policy the monolith does not know' do
    let(:response) { response_with(decisions: [decision(policy_id: non_existing_record_id)]) }

    it 'records nothing for it and reports it', :aggregate_failures do
      allow(Gitlab::AppJsonLogger).to receive(:info)

      service.execute

      expect(Govern::PolicyEvaluation.count).to eq(0)
      expect(Gitlab::AppJsonLogger).to have_received(:info)
        .with(a_hash_including(event: 'govern_unknown_policy'))
    end
  end

  context 'when a policy matches on the gate trigger (the fence)' do
    let(:trigger) { 'project.before_settings_update' }
    let(:policy) do
      create(:govern_policy, :without_namespace, organization: organization,
        trigger_type: 'project.before_settings_update', mode: :enforce)
    end

    let(:response) { response_with(decisions: [decision]) }

    it 'records the proposal evaluation but tracks no enforcement', :aggregate_failures do
      result = service.execute

      expect(Govern::PolicyEvaluation.sole.trigger_type).to eq('project.before_settings_update')
      expect(Govern::PolicyEnforcement.count).to eq(0)
      expect(result.policies).to eq(policy.id => policy)
    end
  end

  context 'when a policy matches on the drift check' do
    let(:trigger) { 'project.scheduled_settings_drift_check' }
    let(:policy) do
      create(:govern_policy, :without_namespace, organization: organization,
        trigger_type: 'project.after_create', mode: :enforce)
    end

    let(:response) { response_with(decisions: [decision(actions: [])]) }

    it 'records the engine-internal trigger and leaves the violation open' do
      service.execute

      expect(Govern::PolicyEvaluation.sole.trigger_type).to eq('project.scheduled_settings_drift_check')
      expect(Govern::PolicyEnforcement.sole.state).to eq('active')
    end
  end

  context 'when the matched policy is in audit mode' do
    let(:policy) do
      create(:govern_policy, :without_namespace, organization: organization,
        trigger_type: 'project.after_create', mode: :audit)
    end

    let(:response) { response_with(decisions: [decision]) }

    it 'dispatches the observing action despite audit mode (US2: the trail IS the rollout)' do
      executor = instance_double(Govern::PolicyEngine::LogAuditTrailExecutor,
        execute: { outcome: :audit_logged, setting: 'request_access_enabled', note: 'recorded' })
      allow(Govern::PolicyEngine::LogAuditTrailExecutor).to receive(:new).and_return(executor)

      service.execute

      expect(executor).to have_received(:execute)
      expect(Govern::PolicyEnforcement.sole.state).to eq('active')
    end
  end

  context 'when the enforcement write fails' do
    let(:response) { response_with(decisions: [decision]) }

    it 'takes the evaluation down with it, so a retry records one row', :aggregate_failures do
      allow_next_instance_of(Govern::PolicyEnforcement) do |enforcement|
        allow(enforcement).to receive(:save!).and_raise(ActiveRecord::StatementInvalid)
      end

      expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Govern::PolicyEvaluation.count).to eq(0)
      expect(Govern::PolicyViolation.count).to eq(0)
    end
  end

  context 'when a decision gates' do
    let(:response) do
      response_with(decisions: [decision(actions: [{ action_type: 'block', message: nil, params: {},
                                                     gating: true }])])
    end

    it 'denies' do
      expect(service.execute.verdict).to eq(:deny)
    end
  end

  context 'when a policy is undecided' do
    let(:response) do
      response_with(decisions: [decision(matched: false, actions: [], reasons: [], error: 'rego broke')],
        undecided: [policy.id])
    end

    it 'is undecidable, records deny fail-closed, and fails the enforcement', :aggregate_failures do
      result = service.execute

      expect(result.verdict).to eq(:undecidable)
      expect(Govern::PolicyEvaluation.sole.verdict).to eq('deny')
      expect(Govern::PolicyEnforcement.sole.state).to eq('failed')
    end
  end

  context 'when the engine faults' do
    let(:response) { nil }

    before do
      allow(engine).to receive(:evaluate).and_raise(RuntimeError, 'store lookup failed: 401')
    end

    it 'fails closed: undecidable, nothing recorded, nothing dispatched', :aggregate_failures do
      expect(Govern::PolicyEngine::LogAuditTrailExecutor).not_to receive(:new)
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(RuntimeError), a_hash_including(subject_id: project.id, trigger: trigger))

      result = service.execute

      expect(result.verdict).to eq(:undecidable)
      expect(result.error).to include('401')
      expect(Govern::PolicyEvaluation.count).to eq(0)
      expect(Govern::PolicyEnforcement.count).to eq(0)
    end
  end

  context 'when the recorder faults' do
    let(:response) { response_with(decisions: [decision]) }

    before do
      allow(Gitlab::PolicyStore).to receive(:record_evaluation)
        .and_raise(Gitlab::PolicyStore::ValidationError, 'verdict is not included in the list')
    end

    # Reporting :undecidable here would say nothing happened, which a
    # partly dispatched evaluation makes untrue.
    it 'propagates rather than reporting an undecidable evaluation' do
      expect { service.execute }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /verdict is not included/)
    end
  end
end
