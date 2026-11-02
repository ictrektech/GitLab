# frozen_string_literal: true

# Shared validation coverage for custom dashboard mutations that accept panel
# visualizations. A panel supplies its visualization as an inline config object
# (`visualizationConfig`).
#
# The including context must:
#   - define `mutation` and `mutation_response`
#   - define `user`
#   - build the mutation `variables` so the dashboard config's panels come from
#     the `panels` let defined here
RSpec.shared_examples 'a custom dashboard mutation validating panel visualizations' do
  context 'when a panel visualization is an invalid config object' do
    let(:panels) do
      [
        {
          title: 'Broken Panel',
          visualizationConfig: { type: 'NotAChartType' },
          gridAttributes: { width: 4, height: 2 }
        }
      ]
    end

    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: user)

      expect(mutation_response['dashboard']).to be_nil
      expect(mutation_response['errors'].join).to match(/must be a valid json schema/)
    end
  end

  context 'when a panel supplies no visualizationConfig' do
    let(:panels) do
      [
        {
          title: 'Empty Panel',
          gridAttributes: { width: 4, height: 2 }
        }
      ]
    end

    it 'returns an argument error' do
      post_graphql_mutation(mutation, current_user: user)

      expect(graphql_errors).to include(a_hash_including('message' => a_string_matching(/visualizationConfig/)))
    end
  end

  context 'when a panel references a visualization by name' do
    let(:panels) do
      [
        {
          title: 'Referenced Panel',
          visualization: 'number',
          gridAttributes: { width: 4, height: 2 }
        }
      ]
    end

    it 'rejects the argument' do
      post_graphql_mutation(mutation, current_user: user)

      expect(graphql_errors).to include(a_hash_including('message' => a_string_matching(/visualization/)))
    end
  end
end
