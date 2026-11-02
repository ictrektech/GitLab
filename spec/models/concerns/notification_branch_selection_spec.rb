# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationBranchSelection, :aggregate_failures, feature_category: :integrations do
  let(:project) { build_stubbed(:project) }
  let(:data) { { object_attributes: { tag: true, ref: 'deleted-tag', sha: 'abc' } } }

  shared_examples 'legacy branch filtering' do
    before do
      allow(project).to receive(:default_branch).and_return('main')
      allow(ProtectedBranch).to receive(:protected?).with(project, 'deleted-tag').and_return(false)
    end

    it 'does not look up containing branches for unresolved tags' do
      integration.branches_to_be_notified = 'default'

      expect(project.repository).not_to receive(:branch_names_contains)
      expect(integration.notify_for_branch?(data)).to be(false)
    end

    using RSpec::Parameterized::TableSyntax

    where(:selection) { ['other', 'default,protected', 'default,other'] }

    with_them do
      it 'does not interpret the deferred branch selections' do
        integration.branches_to_be_notified = selection
        data[:object_attributes][:ref] = 'main'
        allow(ProtectedBranch).to receive(:protected?).with(project, 'main').and_return(false)

        expect(integration.notify_for_branch?(data)).to be(false)
      end
    end
  end

  context 'with a chat integration' do
    let(:integration) { Integrations::Slack.new(project: project) }

    it_behaves_like 'legacy branch filtering'
  end

  context 'with Emails on push' do
    let(:integration) { Integrations::EmailsOnPush.new(project: project) }

    it_behaves_like 'legacy branch filtering'
  end
end
