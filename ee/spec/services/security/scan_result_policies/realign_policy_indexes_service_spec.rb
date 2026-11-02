# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::RealignPolicyIndexesService, feature_category: :security_policy_management do
  include ExclusiveLeaseHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:policy_configuration) { create(:security_orchestration_policy_configuration, project: project) }

  subject(:execute) { described_class.new(project: project, policy_configuration: policy_configuration).execute }

  def create_read(policy_index:, read_index:, read_project: project)
    policy = create(:security_policy, security_orchestration_policy_configuration: policy_configuration,
      policy_index: policy_index)
    rule = create(:approval_policy_rule, security_policy: policy)

    create(:scan_result_policy_read, project: read_project, approval_policy_rule: rule,
      security_orchestration_policy_configuration: policy_configuration,
      orchestration_policy_idx: read_index, rule_idx: rule.rule_index)
  end

  def create_merge_request_rule(merge_request, read, name: 'Policy rule')
    create(:report_approver_rule, :scan_finding, name: name, merge_request: merge_request,
      security_orchestration_policy_configuration: policy_configuration,
      orchestration_policy_idx: read.orchestration_policy_idx, scan_result_policy_read: read)
  end

  context 'when two policies swapped places' do
    let!(:read_a) { create_read(policy_index: 1, read_index: 0) }
    let!(:read_b) { create_read(policy_index: 0, read_index: 1) }
    let(:merge_request) { create(:merge_request, source_project: project) }

    let!(:project_rule) do
      create(:approval_project_rule, project: project, orchestration_policy_idx: 0, scan_result_policy_read: read_a)
    end

    let!(:mr_rule_a) { create_merge_request_rule(merge_request, read_a) }
    let!(:mr_rule_b) { create_merge_request_rule(merge_request, read_b) }

    it 'moves the reads and their approval rules to the current policy index', :aggregate_failures do
      execute

      expect(read_a.reload.orchestration_policy_idx).to eq(1)
      expect(read_b.reload.orchestration_policy_idx).to eq(0)
      expect(project_rule.reload.orchestration_policy_idx).to eq(1)
      expect(mr_rule_a.reload.orchestration_policy_idx).to eq(1)
      expect(mr_rule_b.reload.orchestration_policy_idx).to eq(0)
    end

    it 'moves project rules before merge request rules and locks the reads last', :aggregate_failures do
      log = ActiveRecord::QueryRecorder.new { execute }.log

      project_rules = log.index { |sql| sql.start_with?('UPDATE "approval_project_rules"') }
      merge_request_rules = log.index { |sql| sql.start_with?('UPDATE "approval_merge_request_rules"') }
      locked_read = log.index { |sql| sql.include?('FOR NO KEY UPDATE OF scan_result_policies') }

      expect(project_rules).to be < merge_request_rules
      expect(merge_request_rules).to be < locked_read
    end

    it 'locks the merge request rules and updates them by explicit ids', :aggregate_failures do
      log = ActiveRecord::QueryRecorder.new { execute }.log

      expect(log.grep(/\ASELECT.*FROM "approval_merge_request_rules".*FOR NO KEY UPDATE/m)).not_to be_empty
      updates = log.grep(/\AUPDATE "approval_merge_request_rules"/)
      expect(updates).to all(match(/WHERE "approval_merge_request_rules"."id" (IN \(|= )\d/))
    end

    it 'renews the lease before every UPDATE' do
      renewals = 0
      allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lock|
        allow(lock).to receive(:renew) { renewals += 1 }
      end

      updates = ActiveRecord::QueryRecorder.new { execute }.log.grep(/\AUPDATE/).size

      expect(renewals).to eq(updates)
    end

    context 'when the lease is lost' do
      it 'raises before touching more rows' do
        allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lock|
          allow(lock).to receive(:renew).and_return(false)
        end

        expect { execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
          .and not_change { read_a.reload.orchestration_policy_idx }
      end
    end

    it 'takes an exclusive lease for the policy configuration and project' do
      lease = stub_exclusive_lease(
        "security_policies:realign_policy_indexes:#{policy_configuration.id}:#{project.id}",
        renew: true, timeout: described_class::LOCK_TTL
      )

      expect(lease).to receive(:try_obtain)

      execute
    end

    context 'when the merge request is closed' do
      let(:merge_request) { create(:merge_request, :closed, source_project: project) }

      it 'does not change its approval rules' do
        expect { execute }.not_to change { mr_rule_a.reload.orchestration_policy_idx }
      end
    end

    context 'when the merge request is merged between the temporary shift and the final move' do
      it 'still moves its rules off the temporary index', :aggregate_failures do
        merged = false
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          next if merged || !payload[:sql].start_with?('UPDATE "approval_merge_request_rules"')

          merged = true
          merge_request.update_column(:state_id, MergeRequest.available_states[:merged])
        end

        execute

        expect(merged).to be(true)
        expect(mr_rule_a.reload.orchestration_policy_idx).to eq(1)
        expect(mr_rule_b.reload.orchestration_policy_idx).to eq(0)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    context 'when there are more open merge requests than fit in a batch' do
      let!(:other_merge_request) { create(:merge_request, source_project: project, source_branch: 'other') }
      let!(:other_rule_a) { create_merge_request_rule(other_merge_request, read_a) }
      let!(:other_rule_b) { create_merge_request_rule(other_merge_request, read_b) }

      before do
        stub_const("#{described_class}::MERGE_REQUEST_BATCH_SIZE", 1)
      end

      it 'realigns every batch in its own pair of statements', :aggregate_failures do
        recorder = ActiveRecord::QueryRecorder.new { execute }

        # 2 batches * (1 temporary shift + 1 final move per policy)
        expect(recorder.log.grep(/\AUPDATE "approval_merge_request_rules"/).size).to eq(6)
        expect([mr_rule_a, mr_rule_b, other_rule_a, other_rule_b].map { |r| r.reload.orchestration_policy_idx })
          .to eq([1, 0, 1, 0])
      end
    end

    context 'when there are more stale reads than the policy limits allow' do
      before do
        stub_const("#{described_class}::MAX_STALE_READS", 1)
      end

      it 'raises without changing anything' do
        expect { execute }.to raise_error(described_class::TooManyReadsError)
          .and not_change { read_a.reload.orchestration_policy_idx }
      end
    end
  end

  context 'when three policies rotated' do
    let!(:reads) do
      [create_read(policy_index: 1, read_index: 0), create_read(policy_index: 2, read_index: 1),
        create_read(policy_index: 0, read_index: 2)]
    end

    it 'moves every read to its policy index' do
      execute

      expect(reads.map { |read| read.reload.orchestration_policy_idx }).to eq([1, 2, 0])
    end

    context 'when an open merge request has no approval rules for them' do
      before do
        create(:merge_request, source_project: project)
      end

      it 'still moves every read to its policy index' do
        execute

        expect(reads.map { |read| read.reload.orchestration_policy_idx }).to eq([1, 2, 0])
      end
    end
  end

  context 'when a policy has several reads' do
    let_it_be(:policy) do
      create(:security_policy, security_orchestration_policy_configuration: policy_configuration, policy_index: 1)
    end

    let!(:reads) do
      [0, 1, 2].map do |rule_index|
        rule = create(:approval_policy_rule, security_policy: policy, rule_index: rule_index)
        create(:scan_result_policy_read, project: project, approval_policy_rule: rule,
          security_orchestration_policy_configuration: policy_configuration,
          orchestration_policy_idx: 0, rule_idx: rule_index)
      end
    end

    let!(:project_rules) do
      reads.map do |read|
        create(:approval_project_rule, project: project, orchestration_policy_idx: 0, scan_result_policy_read: read)
      end
    end

    let(:merge_request) { create(:merge_request, source_project: project) }
    let!(:mr_rules) do
      reads.map { |read| create_merge_request_rule(merge_request, read, name: "Rule #{read.rule_idx}") }
    end

    it 'moves all of them and their approval rules together', :aggregate_failures do
      execute

      expect(reads.map { |read| read.reload.orchestration_policy_idx }).to all(eq(1))
      expect(project_rules.map { |rule| rule.reload.orchestration_policy_idx }).to all(eq(1))
      expect(mr_rules.map { |rule| rule.reload.orchestration_policy_idx }).to all(eq(1))
    end

    it 'runs the final move once per policy instead of once per read' do
      recorder = ActiveRecord::QueryRecorder.new { execute }

      # 1 project rule move + 2 temporary shifts + 2 final moves, regardless of the number of reads
      expect(recorder.log.grep(/\AUPDATE/).size).to eq(5)
    end
  end

  context 'when the policy holding an index was deleted' do
    let!(:deleted_read) { create_read(policy_index: -1, read_index: 0) }

    it 'moves the read off the index' do
      expect { execute }.to change { deleted_read.reload.orchestration_policy_idx }.from(0).to(-1)
    end
  end

  context 'when the read belongs to another project' do
    let_it_be(:other_project) { create(:project) }
    let!(:other_read) { create_read(policy_index: 1, read_index: 0, read_project: other_project) }

    it 'does not change it' do
      expect { execute }.not_to change { other_read.reload.orchestration_policy_idx }
    end
  end

  context 'when reads are aligned' do
    before do
      create_read(policy_index: 0, read_index: 0)
    end

    it 'does not update anything' do
      recorder = ActiveRecord::QueryRecorder.new { execute }

      expect(recorder.log.grep(/\AUPDATE/)).to be_empty
    end
  end
end
