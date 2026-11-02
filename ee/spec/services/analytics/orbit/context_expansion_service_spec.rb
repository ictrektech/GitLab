# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::ContextExpansionService, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }

  def execute(type)
    described_class.new(
      user, type: type, id: 7, traversal_path: '1/2/', format: :raw, request_context: nil, env: {}
    ).execute
  end

  it 'returns expansion_unsupported_type without a query for a type that has no expand query' do
    expect(execute('Project')).to eq(error: { code: 'expansion_unsupported_type' })
  end
end
