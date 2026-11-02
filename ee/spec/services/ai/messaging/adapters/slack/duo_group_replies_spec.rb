# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::Adapters::Slack::DuoGroupReplies, feature_category: :integrations do
  using RSpec::Parameterized::TableSyntax

  describe '.text' do
    let(:named) { { 'duo_group_name' => 'Acme' } }

    where(:error, :context, :expected) do
      :duo_group_not_set_up | { 'setup_by' => 'admin', 'setup_url' => 'u' } |
        'Your GitLab administrator can turn it on in the Admin area: u'
      :duo_group_not_set_up | {} | 'An Owner of the top-level group that installed the GitLab for Slack app'
      :duo_group_experiments_off | { 'settings_by_admin' => true } | 'Your GitLab administrator can turn on'
      :duo_group_experiments_off | { 'duo_group_name' => 'Acme' } | 'An Owner of Acme can turn on experiment'
      :duo_group_experiments_off | {} | 'An Owner of the group it runs in can turn on experiment'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'role', 'duo_group_name' => 'Acme' } |
        'Ask an Owner of Acme for access, then mention me again.'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'role' } | 'Ask an Owner of that group for access.'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'seat', 'duo_group_name' => 'Acme' } |
        "You don't have access to GitLab Duo Agent Platform in Acme."
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'seat' } |
        "You don't have access to GitLab Duo Agent Platform in the group it runs in"
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'duo_features_off', 'duo_group_name' => 'Acme' } |
        'GitLab Duo is turned off in Acme.'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'duo_features_off' } |
        'GitLab Duo is turned off in the group it runs in'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'agent_platform_off', 'settings_by_admin' => true } |
        'GitLab Duo Agent Platform is turned off for this instance.'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'agent_platform_off', 'duo_group_name' => 'Acme' } |
        'GitLab Duo Agent Platform is turned off in Acme.'
      :cannot_create_workflow_pipeline | { 'duo_group_refusal' => 'agent_platform_off' } |
        'GitLab Duo Agent Platform is turned off in the group it runs in'
      :usage_quota_exceeded | { 'duo_group_name' => 'Acme' } | 'has no credits left in Acme'
      :usage_quota_exceeded | {} | 'has no credits left. Ask an Owner of the group it runs in'
      :usage_billing_forbidden | { 'duo_group_name' => 'Acme' } | 'has no credits left in Acme'
      :flow_disabled_by_feature_flag | {} | "isn't available for this Slack workspace yet"
    end

    with_them do
      it { expect(described_class.text(error, context)).to include(expected) }
    end

    it 'uses the unnamed reply when the viewer cannot see the Duo group' do
      replies = [
        described_class.text(:duo_group_experiments_off, {}),
        described_class.text(:usage_quota_exceeded, {}),
        *%w[role seat duo_features_off agent_platform_off].map do |refusal|
          described_class.text(:cannot_create_workflow_pipeline, { 'duo_group_refusal' => refusal })
        end
      ]

      expect(replies).to all(be_present)
      expect(replies).to all(include('the group it runs in').or(include('that group')))
      expect(replies).not_to include(a_string_including('%{group}'))
    end

    it 'returns nil for other errors, so the adapter keeps its own reply' do
      expect(described_class.text(:forbidden, named)).to be_nil
    end
  end
end
