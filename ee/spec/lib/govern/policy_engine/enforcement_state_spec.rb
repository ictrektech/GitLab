# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::EnforcementState, feature_category: :security_policy_management do
  let(:enforce_policy) { build_stubbed(:govern_policy, mode: :enforce) }
  let(:audit_policy) { build_stubbed(:govern_policy, mode: :audit) }

  def state_for(policy, decision, outcomes = [])
    described_class.for(decision: decision, policy: policy, outcomes: outcomes)
  end

  it 'fails when the policy could not be decided' do
    expect(state_for(enforce_policy, { matched: true, error: 'rego broke' })).to eq(:failed)
  end

  it 'completes when nothing was violated' do
    expect(state_for(enforce_policy, { matched: false, error: nil })).to eq(:completed)
  end

  it 'leaves the violation open for a policy that does not enforce' do
    expect(state_for(audit_policy, { matched: true, error: nil })).to eq(:active)
  end

  it 'completes when a write restored compliance' do
    expect(state_for(enforce_policy, { matched: true, error: nil }, [{ outcome: :converged }])).to eq(:completed)
    expect(state_for(enforce_policy, { matched: true, error: nil }, [{ outcome: :converge_noop }])).to eq(:completed)
  end

  it 'fails when a write did not stick' do
    [:converge_ineffective, :converge_rejected, :converge_conflict].each do |outcome|
      expect(state_for(enforce_policy, { matched: true, error: nil }, [{ outcome: outcome }])).to eq(:failed)
    end
  end

  it 'fails when the audit trail could not be written' do
    outcomes = [{ outcome: :audit_log_failed }]

    expect(state_for(enforce_policy, { matched: true, error: nil }, outcomes)).to eq(:failed)
  end

  it 'keeps an audit policy active when its audit write failed: the mode check wins' do
    outcomes = [{ outcome: :audit_log_failed }]

    expect(state_for(audit_policy, { matched: true, error: nil }, outcomes)).to eq(:active)
  end

  it 'lets one unresolved setting fail an otherwise converged enforcement' do
    outcomes = [{ outcome: :converged }, { outcome: :converge_rejected }]

    expect(state_for(enforce_policy, { matched: true, error: nil }, outcomes)).to eq(:failed)
  end

  it 'leaves the violation open when an enforce policy dispatched nothing that resolves it' do
    outcomes = [{ outcome: :audit_logged }]

    expect(state_for(enforce_policy, { matched: true, error: nil }, outcomes)).to eq(:active)
  end

  it 'reports only states the enforcement row can store' do
    expect(Govern::PolicyEnforcement.states.keys).to include(*described_class::ALL.map(&:to_s))
  end
end
