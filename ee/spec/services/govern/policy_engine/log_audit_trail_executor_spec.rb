# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::LogAuditTrailExecutor, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:actor) { create(:user, maintainer_of: [project]) }

  let(:policy) do
    build_stubbed(:govern_policy, :without_namespace, organization: project.organization,
      trigger_type: 'project.after_create', mode: :audit)
  end

  let(:action) { { action_type: 'log_audit_trail', message: nil, params: {}, gating: false } }

  let(:decision) do
    {
      policy_id: policy.id,
      matched: true,
      actions: [action],
      reasons: [{ message: 'drift', details: { 'path' => 'request_access_enabled', 'expected' => false,
                                               'actual' => true } }],
      error: nil
    }
  end

  subject(:executor) do
    described_class.new(subject: project, policy: policy, decision: decision, action: action, actor: actor)
  end

  before do
    stub_licensed_features(audit_events: true, extended_audit_events: true, admin_audit_log: true)
  end

  it 'streams one event carrying the policy and the violations, and stores none' do
    # An organization-level policy (no namespace) logs at instance scope.
    expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
      a_hash_including(
        name: described_class::EVENT_NAME,
        scope: an_instance_of(::Gitlab::Audit::InstanceScope),
        target: project,
        message: a_string_including('request_access_enabled expected false actual true'),
        additional_details: a_hash_including(
          govern_policy_id: policy.id,
          violations: contain_exactly(
            a_hash_including('path' => 'request_access_enabled', 'expected' => false, 'actual' => true)
          )
        )
      )
    ).and_call_original

    expect { executor.execute }.not_to change { AuditEvents::InstanceAuditEvent.count }
  end

  it 'reports the outcome with the violated settings' do
    result = executor.execute

    expect(result[:outcome]).to eq(:audit_logged), -> { result.inspect }
    expect(result[:setting]).to eq('request_access_enabled')
  end

  it 'scopes the event to the policy namespace when the policy is group-authored' do
    group_policy = build_stubbed(:govern_policy, namespace: group, organization: group.organization,
      trigger_type: 'project.after_create', mode: :audit)

    expect(::Gitlab::Audit::Auditor).to receive(:audit).with(a_hash_including(scope: group))

    described_class.new(subject: project, policy: group_policy, decision: decision,
      action: action, actor: actor).execute
  end

  it 'fails soft: an auditor fault becomes an outcome, not an exception' do
    allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'stream down')

    expect(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
      .with(an_instance_of(StandardError), govern_policy_id: policy.id, subject_id: project.id,
        subject_type: 'Project')

    result = executor.execute

    expect(result[:outcome]).to eq(:audit_log_failed)
    expect(result[:note]).to include('stream down')
  end

  it 'tracks the fault under the class of the subject, which is not always a project' do
    environment = build_stubbed(:environment, project: project)
    deployment_policy = build_stubbed(:govern_policy, :without_namespace, organization: project.organization,
      trigger_type: 'deployment_requested', mode: :audit)

    allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'stream down')

    expect(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
      .with(an_instance_of(StandardError), govern_policy_id: deployment_policy.id, subject_id: environment.id,
        subject_type: 'Environment')

    described_class.new(subject: environment, policy: deployment_policy, decision: decision,
      action: action, actor: actor).execute
  end

  it 'fails soft on a malformed decision, which the outcome itself has to read' do
    decision[:reasons] = 'not a list'

    # The tracking helper raises in the test environment, which would hide
    # the production path this example exists for.
    expect(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)

    result = executor.execute

    expect(result[:outcome]).to eq(:audit_log_failed)
    expect(result[:setting]).to eq('')
  end
end
