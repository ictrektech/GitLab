# frozen_string_literal: true

require "spec_helper"

RSpec.describe MergeRequests::Mergeability::CheckApprovedService, feature_category: :code_review_workflow do
  subject(:check_approved) { described_class.new(merge_request: merge_request, params: params) }

  let_it_be(:merge_request) { build(:merge_request) }
  let(:params) { { skip_approved_check: skip_check } }
  let(:skip_check) { false }

  it_behaves_like 'mergeability check service', :not_approved, 'Checks whether the merge request is approved'

  describe "#execute" do
    let(:result) { check_approved.execute }

    before do
      allow(merge_request)
        .to receive(:approval_feature_available?)
        .and_return(approval_feature_available?)
    end

    context 'when approval feature is available' do
      let(:approval_feature_available?) { true }

      before do
        allow(merge_request).to receive(:approved?).and_return(approved)
      end

      context 'when the merge request is temporarily unapproved' do
        let(:approved) { true }

        before do
          allow(merge_request).to receive(:temporarily_unapproved?).and_return(true)
        end

        it "returns a check result with status checking" do
          expect(result.status)
            .to eq Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS
        end
      end

      context "when the merge request is approved" do
        let(:approved) { true }

        it "returns a check result with status success" do
          expect(result.status)
            .to eq Gitlab::MergeRequests::Mergeability::CheckResult::SUCCESS_STATUS
        end
      end

      context "when the merge request is not approved" do
        let(:approved) { false }

        it "returns a check result with status failure" do
          expect(result.status)
            .to eq Gitlab::MergeRequests::Mergeability::CheckResult::FAILED_STATUS
          expect(result.payload[:identifier]).to eq(:not_approved)
        end
      end
    end

    context 'when approval feature is not available' do
      let(:approval_feature_available?) { false }

      it 'returns a check result with inactive status' do
        expect(result.status).to eq Gitlab::MergeRequests::Mergeability::CheckResult::INACTIVE_STATUS
      end
    end
  end

  describe '#skip?' do
    subject { check_approved.skip? }

    context 'when skip check is true' do
      let(:skip_check) { true }

      it { is_expected.to be true }
    end

    context 'when skip check is false' do
      let(:skip_check) { false }

      it { is_expected.to be false }
    end
  end

  describe '#cacheable?' do
    subject(:cacheable) { check_approved.cacheable? }

    it { is_expected.to be true }

    context 'when the merge request is temporarily unapproved' do
      before do
        allow(merge_request).to receive(:temporarily_unapproved?).and_return(true)
      end

      it { is_expected.to be false }
    end
  end

  describe '#cache_key' do
    let(:id) { 42 }
    let(:expected_cache_key) { format(described_class::CACHE_KEY, id: id) }

    before do
      allow(merge_request).to receive(:id).and_return(id)
    end

    it 'returns the expected cache key' do
      expect(check_approved.cache_key).to eq(expected_cache_key)
    end
  end

  describe '#cache_ttl' do
    it 'returns 60 seconds' do
      expect(check_approved.cache_ttl).to eq 60.seconds
    end
  end

  describe '#invalidate' do
    let(:results_store) { instance_double(Gitlab::MergeRequests::Mergeability::ResultsStore) }

    before do
      allow(Gitlab::MergeRequests::Mergeability::ResultsStore)
        .to receive(:new).with(merge_request: merge_request).and_return(results_store)
    end

    it 'calls delete on the results store' do
      expect(results_store).to receive(:delete).with(merge_check: check_approved)

      check_approved.invalidate
    end
  end

  describe 'temporarily unapproved lookups', :clean_gitlab_redis_shared_state do
    let_it_be(:merge_request) { create(:merge_request) }
    let(:unapproved_key) { "mr_#{merge_request.id}_cannot_merge" }

    before_all do
      create(:approval_merge_request_rule, merge_request: merge_request, approvals_required: 1, users: [create(:user)])
    end

    before do
      stub_licensed_features(merge_request_approvers: true)
    end

    def unapproved_key_reads(use_cache: true)
      control = RedisCommands::Recorder.new do
        check = described_class.new(merge_request: MergeRequest.find(merge_request.id), params: {})
        check.cacheable? if use_cache
        check.execute
      end

      control.by_command('exists').count { |command| command.include?(unapproved_key) }
    end

    it 'reads the temporarily unapproved key once' do
      expect(unapproved_key_reads).to eq(1)
    end

    it 'reads the temporarily unapproved key for every caller when the results cache is not used' do
      expect(unapproved_key_reads(use_cache: false)).to eq(2)
    end

    context 'when approval_check_fewer_lookups is disabled' do
      before do
        stub_feature_flags(approval_check_fewer_lookups: false)
      end

      it 'reads the temporarily unapproved key for every caller' do
        expect(unapproved_key_reads).to eq(3)
      end
    end
  end
end
