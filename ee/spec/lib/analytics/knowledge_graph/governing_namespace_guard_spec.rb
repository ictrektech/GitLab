# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::GoverningNamespaceGuard, feature_category: :knowledge_graph do
  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:group_a) { create(:group, name: 'group-a') }
  let_it_be(:group_b) { create(:group, name: 'group-b') }

  let(:candidates) { [group_a, group_b] }
  let(:single_candidate_fallback) { nil }
  let(:finder) do
    instance_double(
      Analytics::KnowledgeGraph::GoverningNamespaceFinder,
      candidates: candidates,
      single_candidate_fallback: single_candidate_fallback
    )
  end

  before do
    allow(Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for).with(user).and_return(finder)
    stub_saas_features(gitlab_com_subscriptions: true)
  end

  describe '.ensure_selected!' do
    subject(:ensure_selected) { described_class.ensure_selected!(user) }

    context 'when not on SaaS' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'does not raise even with several candidates' do
        expect { ensure_selected }.not_to raise_error
      end
    end

    context 'when the preference is unset and several candidates exist' do
      it 'raises an error carrying the shared contract', :aggregate_failures do
        expect { ensure_selected }.to raise_error(described_class::RequiredError) do |error|
          expect(error.contract.as_json).to eq(
            code: 'billing_namespace_required',
            message: s_('Orbit|Select a default group in your preferences to run GitLab Orbit queries.'),
            deep_link: Gitlab::Routing.url_helpers.profile_preferences_url,
            candidates: [
              { id: group_a.id, name: 'group-a' },
              { id: group_b.id, name: 'group-b' }
            ]
          )
        end
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(knowledge_graph_billing: false)
      end

      it 'does not raise' do
        expect { ensure_selected }.not_to raise_error
      end
    end

    context 'when the preference is set' do
      before do
        allow(finder).to receive(:eligible?).with(group_a.id).and_return(true)
        user.user_preference.update!(knowledge_graph_governing_namespace_id: group_a.id)
      end

      it 'does not raise' do
        expect { ensure_selected }.not_to raise_error
      end
    end

    context 'when exactly one candidate exists' do
      let(:candidates) { [group_a] }
      let(:single_candidate_fallback) { group_a }

      it 'does not raise because the fallback attributes usage' do
        expect { ensure_selected }.not_to raise_error
      end
    end

    context 'when no candidates exist' do
      let(:candidates) { [] }

      it 'raises an error with an empty candidates list' do
        expect { ensure_selected }.to raise_error(described_class::RequiredError) do |error|
          expect(error.contract.as_json[:candidates]).to be_empty
        end
      end
    end

    context 'when there is no user' do
      it 'does not raise' do
        expect { described_class.ensure_selected!(nil) }.not_to raise_error
      end
    end
  end
end
