# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::GoverningNamespaceError, feature_category: :knowledge_graph do
  let_it_be(:group_a) { create(:group, name: 'group-a') }
  let_it_be(:group_b) { create(:group, name: 'group-b') }

  let(:candidates) { [group_a, group_b] }

  subject(:error) { described_class.new(candidates) }

  describe '#as_json' do
    subject(:json) { error.as_json }

    it 'includes the stable code and message', :aggregate_failures do
      expect(json[:code]).to eq('billing_namespace_required')
      expect(json[:message]).to eq(s_('Orbit|Select a default group in your preferences to run GitLab Orbit queries.'))
    end

    it 'includes a deep link to the preferences page' do
      expect(json[:deep_link]).to eq(Gitlab::Routing.url_helpers.profile_preferences_url)
    end

    it 'serializes each candidate as an id/name pair' do
      expect(json[:candidates]).to match_array(
        [
          { id: group_a.id, name: 'group-a' },
          { id: group_b.id, name: 'group-b' }
        ]
      )
    end

    context 'when the user has no candidate namespaces' do
      let(:candidates) { [] }

      it 'returns an empty candidates array' do
        expect(json[:candidates]).to eq([])
      end
    end
  end
end
