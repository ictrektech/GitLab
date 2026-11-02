# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ApprovalSettings, feature_category: :security_policy_management do
  describe '.by_setting' do
    it 'names the column a catalog setting writes' do
      entry = described_class.by_setting('allow_author_approval')

      expect(entry.column).to eq(:merge_requests_author_approval)
      expect(entry).not_to be_inverted
    end

    it 'marks the settings whose column disables what the catalog allows' do
      %w[allow_committer_approval allow_overrides_to_approver_list_per_merge_request
        retain_approvals_on_push].each do |setting|
        expect(described_class.by_setting(setting)).to be_inverted
      end
    end

    it 'is nil for a setting it does not cover' do
      expect(described_class.by_setting('request_access_enabled')).to be_nil
    end
  end

  describe '.by_column' do
    it 'reads the same table from the column side' do
      entry = described_class.by_column('merge_requests_disable_committers_approval')

      expect(entry.setting).to eq('allow_committer_approval')
      expect(entry).to be_inverted
    end

    it 'is nil for a column it does not cover' do
      expect(described_class.by_column('request_access_enabled')).to be_nil
    end
  end

  describe '#convert' do
    it 'passes a value through when the column agrees with the catalog' do
      expect(described_class.by_setting('allow_author_approval').convert(true)).to be(true)
    end

    it 'negates a value when the column disagrees, in both directions' do
      entry = described_class.by_setting('retain_approvals_on_push')

      expect(entry.convert(true)).to be(false)
      expect(entry.convert(false)).to be(true)
    end

    it 'reads a truthy param as a boolean, so uncast form input converts' do
      entry = described_class.by_column('merge_requests_disable_committers_approval')

      expect(entry.convert('1')).to be(false)
      expect(entry.convert('0')).to be(true)
    end
  end

  it 'covers every approval setting the catalog knows, once per column' do
    expect(described_class.settings).to contain_exactly(
      'allow_author_approval', 'allow_committer_approval',
      'allow_overrides_to_approver_list_per_merge_request', 'retain_approvals_on_push')
    expect(described_class.columns).to contain_exactly(
      'merge_requests_author_approval', 'merge_requests_disable_committers_approval',
      'disable_overriding_approvers_per_merge_request', 'reset_approvals_on_push')
  end
end
