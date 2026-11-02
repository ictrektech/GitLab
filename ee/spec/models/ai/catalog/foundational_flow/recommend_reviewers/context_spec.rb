# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RecommendReviewers::Context, feature_category: :code_review_workflow do
  describe '.call' do
    subject(:data) { described_class.call(resource: merge_request) }

    let_it_be_with_reload(:project) { create(:project) }
    let_it_be_with_refind(:approver) { create(:user, developer_of: project) }
    let_it_be_with_reload(:other_approver) { create(:user, developer_of: project) }
    let_it_be_with_reload(:current_reviewer) { create(:user, developer_of: project) }

    let_it_be_with_refind(:merge_request) do
      create(:merge_request, source_project: project, target_project: project) do |mr|
        mr.reviewers << current_reviewer
      end
    end

    let_it_be_with_refind(:required_rule) do
      create(:code_owner_rule,
        merge_request: merge_request,
        name: '*.rb',
        section: 'codeowners',
        approvals_required: 1,
        users: [approver])
    end

    let_it_be(:optional_rule, freeze: false) do
      create(:approval_merge_request_rule,
        merge_request: merge_request,
        name: 'Optional Rule',
        rule_type: :regular,
        approvals_required: 0,
        users: [other_approver])
    end

    let_it_be(:protected_branch, freeze: false) do
      create(:protected_branch, project: project, name: merge_request.target_branch, code_owner_approval_required: true)
    end

    before do
      stub_licensed_features(
        merge_request_approvers: true,
        code_owners: true,
        code_owner_approval_required: true
      )
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
    end

    def code_owner_rule_data
      data['approval_rules'].find { |rule| rule['section'] == 'codeowners' }
    end

    it 'is valid against the agent_platform_recommend_reviewers_context schema' do
      schema_path = Rails.root.join(
        'app/validators/json_schemas/agent_platform/agent_platform_recommend_reviewers_context/1.0.0.json'
      )
      schema = JSONSchemer.schema(schema_path)

      expect(schema.valid?(data)).to be(true), schema.validate(data).to_a.inspect
    end

    it 'includes current reviewers' do
      expect(data['current_reviewers']).to contain_exactly(
        { 'id' => current_reviewer.id }
      )
    end

    it 'includes optional regular and code owner rules' do
      # Without this the branch requires code owner approval, which wraps *.md up to 1
      # and the rule would be kept by approvals_required rather than by being a code owner rule.
      protected_branch.update!(code_owner_approval_required: false)

      create(:code_owner_rule,
        merge_request: merge_request,
        name: '*.md',
        section: 'docs',
        approvals_required: 0,
        users: [other_approver])

      rule_names = data['approval_rules'].pluck('name')
      expect(rule_names).to contain_exactly('*.rb', '*.md', 'Optional Rule')
    end

    context 'with optional any approver and policy rules' do
      before do
        stub_licensed_features(
          merge_request_approvers: true,
          code_owners: true,
          code_owner_approval_required: true,
          multiple_approval_rules: true
        )
        create(:any_approver_rule, merge_request: merge_request, approvals_required: 0)
        create(:report_approver_rule, :scan_finding, merge_request: merge_request, approvals_required: 0,
          users: [other_approver])
      end

      it 'excludes them' do
        rule_names = data['approval_rules'].pluck('name')
        expect(rule_names).to contain_exactly('*.rb', 'Optional Rule')
      end
    end

    context 'with multiple required rules' do
      before do
        create(:code_owner_rule,
          merge_request: merge_request,
          name: '*.py',
          section: 'codeowners',
          approvals_required: 1,
          users: [other_approver])
      end

      it 'returns an entry per rule' do
        rule_names = data['approval_rules'].pluck('name')
        expect(rule_names).to contain_exactly('*.rb', '*.py', 'Optional Rule')
      end
    end

    context 'with multiple code owner rules sharing a section and an approver set' do
      before do
        create(:code_owner_rule,
          merge_request: merge_request,
          name: '*.py',
          section: 'codeowners',
          approvals_required: 1,
          users: [approver])
      end

      it 'collapses them into a single rule' do
        expect(data['approval_rules'].pluck('name')).to contain_exactly('*.rb, *.py', 'Optional Rule')
        expect(code_owner_rule_data['eligible_approvers'].pluck('id')).to contain_exactly(approver.id)
      end
    end

    it 'includes the rule id, type, name, section, and approvals_required' do
      expect(code_owner_rule_data).to include(
        'id' => required_rule.id,
        'type' => 'merge_request_rule',
        'name' => '*.rb',
        'section' => 'codeowners',
        'approvals_required' => 1
      )
    end

    context 'when the required rule originates from a project-level approval rule' do
      let_it_be_with_reload(:solo_project) { create(:project) }
      let_it_be_with_refind(:solo_approver) { create(:user, developer_of: solo_project) }
      let_it_be(:solo_merge_request) do
        create(:merge_request, source_project: solo_project, target_project: solo_project)
      end

      let_it_be(:solo_project_rule) do
        create(:approval_project_rule, project: solo_project, approvals_required: 1, users: [solo_approver])
      end

      before do
        stub_licensed_features(merge_request_approvers: true)
      end

      it 'reports the type as project_rule' do
        result = described_class.call(resource: solo_merge_request)
        rule_data = result['approval_rules'].find { |r| r['name'] == solo_project_rule.name }

        expect(rule_data).to include('id' => solo_project_rule.id, 'type' => 'project_rule')
      end
    end

    it 'serializes eligible approvers without the fields that have no value' do
      approver_data = code_owner_rule_data['eligible_approvers'].first

      expect(approver_data).to eq('id' => approver.id, 'busy' => false, 'pending_reviews' => 0)
    end

    context 'when an approver has pending reviews' do
      let_it_be(:other_mr, freeze: false) do
        create(:merge_request, source_project: project, target_project: project, source_branch: 'other-branch') do |mr|
          mr.merge_request_reviewers.create!(reviewer: approver, state: :unreviewed)
        end
      end

      it 'returns the count of open reviews' do
        approver_data = code_owner_rule_data['eligible_approvers'].first
        expect(approver_data['pending_reviews']).to eq(1)
      end
    end

    context 'when an approver has responded to open reviews' do
      before_all do
        %i[reviewed approved requested_changes].each do |state|
          create(:merge_request, source_project: project, target_project: project,
            source_branch: "#{state}-branch") do |mr|
            mr.merge_request_reviewers.create!(reviewer: approver, state: state)
          end
        end

        2.times do |i|
          create(:merge_request, :merged, source_project: project, target_project: project,
            source_branch: "merged-branch-#{i}") do |mr|
            mr.merge_request_reviewers.create!(reviewer: approver, state: :approved)
          end
        end
      end

      it 'counts each open one as half a review' do
        approver_data = code_owner_rule_data['eligible_approvers'].first
        expect(approver_data['pending_reviews']).to eq(2)
      end

      context 'when not running in Sidekiq', :use_clean_rails_memory_store_caching do
        before do
          allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(false)
        end

        it 'does not count uncached responded reviews' do
          expect(code_owner_rule_data['eligible_approvers'].first['pending_reviews']).to eq(0)
        end

        it 'uses the cached count' do
          Rails.cache.write(['recommend_reviewers', approver.id, 'responded_reviews_count'], 3)

          expect(code_owner_rule_data['eligible_approvers'].first['pending_reviews']).to eq(2)
        end
      end
    end

    context 'when more approvers miss the cache than the uncached limit', :use_clean_rails_memory_store_caching do
      let_it_be(:extra_approver) { create(:user, developer_of: project) }

      before do
        stub_const("#{described_class}::MAX_UNCACHED_RESPONDED_COUNTS", 1)
        Rails.cache.write(['recommend_reviewers', other_approver.id, 'responded_reviews_count'], 0)
        required_rule.users << extra_approver

        create(:merge_request, source_project: project, target_project: project,
          source_branch: 'pending-branch') do |mr|
          mr.merge_request_reviewers.create!(reviewer: approver, state: :unreviewed)
        end

        [approver, extra_approver].each do |user|
          create(:merge_request, source_project: project, target_project: project,
            source_branch: "approved-#{user.id}") do |mr|
            mr.merge_request_reviewers.create!(reviewer: user, state: :approved)
          end
        end
      end

      def pending_reviews_by_id
        code_owner_rule_data['eligible_approvers'].to_h { |a| [a['id'], a['pending_reviews']] }
      end

      it 'counts responded reviews only for the least loaded approvers' do
        expect(pending_reviews_by_id).to eq(approver.id => 1, extra_approver.id => 1)
      end

      it 'still uses cached counts beyond the limit' do
        Rails.cache.write(['recommend_reviewers', approver.id, 'responded_reviews_count'], 1)

        expect(pending_reviews_by_id).to eq(approver.id => 2, extra_approver.id => 1)
      end
    end

    context 'when an approver was recently active' do
      let(:last_activity_date) { Date.new(2026, 4, 28) }

      before do
        approver.update!(last_activity_on: last_activity_date)
      end

      it 'returns the last activity date as ISO 8601' do
        approver_data = code_owner_rule_data['eligible_approvers'].first
        expect(approver_data['last_activity_on']).to eq(last_activity_date.iso8601)
      end
    end

    context 'when an approver is busy' do
      before do
        create(:user_status, user: approver, availability: :busy, message: 'on call')
      end

      it 'sets busy to true and includes the message' do
        approver_data = code_owner_rule_data['eligible_approvers'].first

        expect(approver_data['busy']).to be(true)
        expect(approver_data['status_message']).to eq('on call')
      end
    end

    context 'when an approver has a timezone preference' do
      before do
        approver.user_preference.update!(timezone: 'Australia/Melbourne')
      end

      context 'with AEST (no DST)' do
        around do |example|
          # May 1: Melbourne is UTC+10 (AEST), so 03:00 UTC -> 13:00 local
          travel_to(Time.utc(2026, 5, 1, 3, 0)) { example.run }
        end

        it 'computes the local time using the standard offset' do
          approver_data = code_owner_rule_data['eligible_approvers'].first
          expect(approver_data['local_time']).to eq('13:00')
        end
      end

      context 'with AEDT (DST)' do
        around do |example|
          # January 1: Melbourne is UTC+11 (AEDT), so 03:00 UTC -> 14:00 local
          travel_to(Time.utc(2026, 1, 1, 3, 0)) { example.run }
        end

        it 'computes the local time using the daylight saving offset' do
          approver_data = code_owner_rule_data['eligible_approvers'].first
          expect(approver_data['local_time']).to eq('14:00')
        end
      end
    end

    context 'when an approver has no timezone set' do
      before do
        approver.user_preference.update!(timezone: '')
      end

      it 'omits local_time' do
        approver_data = code_owner_rule_data['eligible_approvers'].first
        expect(approver_data).not_to have_key('local_time')
      end
    end

    context 'when an approver has a stored timezone that is no longer valid' do
      before do
        approver.user_preference.save!
        approver.user_preference.update_column(:timezone, 'Invalid/Zone')
      end

      it 'omits local_time' do
        approver_data = code_owner_rule_data['eligible_approvers'].first
        expect(approver_data).not_to have_key('local_time')
      end
    end

    describe 'eligible approvers limit' do
      let(:limit) { 2 }

      before do
        stub_const("#{described_class}::MIN_APPROVERS_PER_RULE", 1)
        stub_const("#{described_class}::MAX_APPROVERS_PER_RULE", limit)
      end

      context 'when at or below the limit' do
        it 'returns all approvers without sorting' do
          rule_data = code_owner_rule_data
          expect(rule_data['eligible_approvers'].map { |a| a['id'] }).to contain_exactly(approver.id)
        end
      end

      context 'when over the limit' do
        let_it_be_with_refind(:extra_approver_a) { create(:user, developer_of: project) }
        let_it_be_with_refind(:extra_approver_b) { create(:user, developer_of: project) }

        before do
          required_rule.users << [extra_approver_a, extra_approver_b]
        end

        it 'caps the eligible approvers at the limit' do
          rule_data = code_owner_rule_data
          expect(rule_data['eligible_approvers'].size).to eq(limit)
        end

        it 'prioritises non-busy approvers' do
          create(:user_status, user: extra_approver_a, availability: :busy)

          rule_data = code_owner_rule_data
          approver_ids = rule_data['eligible_approvers'].map { |a| a['id'] }

          expect(approver_ids).not_to include(extra_approver_a.id)
        end

        it 'prioritises approvers with fewer pending reviews' do
          other_mr = create(:merge_request, source_project: project, source_branch: 'busy-branch')
          other_mr.merge_request_reviewers.create!(reviewer: extra_approver_a, state: :unreviewed)

          rule_data = code_owner_rule_data
          approver_ids = rule_data['eligible_approvers'].map { |a| a['id'] }

          expect(approver_ids).not_to include(extra_approver_a.id)
        end

        it 'prioritises non-busy first, then by pending reviews' do
          # 3 candidates (limit = 2):.
          # - approver: not busy, 0 pending          -> kept
          # - extra_approver_a: not busy, 1 pending  -> kept (non-busy beats busy)
          # - extra_approver_b: busy, 0 pending      -> excluded
          create(:user_status, user: extra_approver_b, availability: :busy)
          other_mr = create(:merge_request, source_project: project, source_branch: 'busy-branch')
          other_mr.merge_request_reviewers.create!(reviewer: extra_approver_a, state: :unreviewed)

          rule_data = code_owner_rule_data
          approver_ids = rule_data['eligible_approvers'].map { |a| a['id'] }

          expect(approver_ids).to contain_exactly(approver.id, extra_approver_a.id)
        end

        it 'adds responded reviews only for the approvers that are kept' do
          create(:user_status, user: extra_approver_b, availability: :busy)
          other_mr = create(:merge_request, source_project: project, source_branch: 'approved-branch')
          other_mr.merge_request_reviewers.create!(reviewer: extra_approver_a, state: :approved)
          read_keys = []
          allow(Rails.cache).to receive(:read_multi).and_wrap_original do |method, *keys|
            read_keys.concat(keys)
            method.call(*keys)
          end

          approvers = code_owner_rule_data['eligible_approvers'].to_h { |a| [a['id'], a['pending_reviews']] }

          expect(approvers).to eq(approver.id => 0, extra_approver_a.id => 1)
          expect(read_keys).not_to include(['recommend_reviewers', extra_approver_b.id, 'responded_reviews_count'])
        end
      end
    end

    describe 'approver budget shared between rules' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:extra_approvers) { create_list(:user, 4, developer_of: project) }

      before do
        stub_const("#{described_class}::MIN_APPROVERS_PER_RULE", 2)
        stub_const("#{described_class}::MAX_APPROVERS_PER_RULE", 4)
        stub_const("#{described_class}::MAX_TOTAL_APPROVERS", 10)

        required_rule.users << extra_approvers

        extra_rules.times do |i|
          create(:code_owner_rule,
            merge_request: merge_request,
            name: "*.#{i}",
            section: "section #{i}",
            approvals_required: 1,
            users: [other_approver])
        end
      end

      where(:extra_rules, :expected_limit) do
        0 | 4
        1 | 3
        4 | 2
      end

      with_them do
        it 'divides the budget between the rules within the per-rule bounds' do
          expect(code_owner_rule_data['eligible_approvers'].size).to eq(expected_limit)
        end
      end
    end

    describe 'query performance', :use_clean_rails_memory_store_caching do
      def build_for(mr)
        described_class.call(resource: MergeRequest.find(mr.id))
      end

      it 'does not produce N+1 queries when there are many approvers (warm cache)' do
        build_for(merge_request)

        control = ActiveRecord::QueryRecorder.new { build_for(merge_request) }

        extra_approvers = create_list(:user, 3, developer_of: project)
        extra_approvers.each do |u|
          create(:user_status, user: u)
          u.user_preference.update!(timezone: 'Australia/Melbourne')
        end
        required_rule.users << extra_approvers
        build_for(merge_request)

        expect { build_for(merge_request) }.not_to exceed_all_query_limit(control).allow_skip_cache_inconsistency
      end

      it 'runs at most MAX_UNCACHED_RESPONDED_COUNTS responded-review counts on a cold cache' do
        stub_const("#{described_class}::MAX_UNCACHED_RESPONDED_COUNTS", 2)
        required_rule.users << create_list(:user, 3, developer_of: project)

        recorder = ActiveRecord::QueryRecorder.new { build_for(merge_request) }

        states = MergeRequestReviewer.states.values_at(*described_class::RESPONDED_REVIEW_STATES).join(', ')
        responded_counts = recorder.log.grep(/"merge_request_reviewers"\."state" IN \(#{states}\)/)
        expect(responded_counts.size).to eq(2)
      end
    end

    context 'when the only required rule is the synthetic any_approver rule' do
      let_it_be(:any_project, freeze: false) { create(:project, :repository) }
      let_it_be(:any_author) { create(:user, developer_of: any_project) }
      let_it_be(:any_developer) { create(:user, developer_of: any_project) }
      let_it_be(:any_maintainer) { create(:user, maintainer_of: any_project) }
      let_it_be(:any_reporter) { create(:user, reporter_of: any_project) }

      let_it_be_with_refind(:any_merge_request) do
        create(:merge_request, source_project: any_project, target_project: any_project, author: any_author)
      end

      let_it_be(:any_approver_rule) do
        create(:any_approver_rule, merge_request: any_merge_request, approvals_required: 1)
      end

      subject(:data) { described_class.call(resource: any_merge_request) }

      it 'surfaces the "All Members" rule with the members that can approve', :aggregate_failures do
        rule = data['approval_rules'].find { |r| r['name'] == 'All Members' }

        expect(rule['approvals_required']).to eq(1)
        expect(rule['eligible_approvers'].pluck('id')).to include(any_developer.id, any_maintainer.id)
      end

      it 'excludes the author and the members that cannot approve' do
        approver_ids = data['approval_rules'].first['eligible_approvers'].pluck('id')

        expect(approver_ids).not_to include(any_author.id, any_reporter.id)
      end

      context 'when a bot or service account is a project member' do
        let_it_be(:project_bot) { create(:user, :project_bot, developer_of: any_project) }
        let_it_be(:service_account) { create(:user, :service_account, developer_of: any_project) }

        it 'excludes bots and service accounts' do
          approver_ids = data['approval_rules'].first['eligible_approvers'].pluck('id')

          expect(approver_ids).not_to include(project_bot.id, service_account.id)
        end
      end

      context 'when only maintainers can merge into the target branch' do
        before do
          create(:protected_branch, :maintainers_can_merge, :no_one_can_push,
            project: any_project, name: any_merge_request.target_branch)
        end

        it 'narrows the candidates to the members that can merge', :aggregate_failures do
          approver_ids = data['approval_rules'].first['eligible_approvers'].pluck('id')

          expect(approver_ids).to include(any_maintainer.id)
          expect(approver_ids).not_to include(any_developer.id)
        end
      end

      context 'when there are more candidates than the limit' do
        before do
          stub_const("#{described_class}::MIN_APPROVERS_PER_RULE", 1)
          stub_const("#{described_class}::MAX_TOTAL_APPROVERS", 1)
        end

        it 'caps the candidates at the shared limit' do
          approver_ids = data['approval_rules'].first['eligible_approvers'].pluck('id')

          expect(approver_ids.size).to eq(1)
        end
      end
    end
  end
end
