# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying security scan profile variables', feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  let(:scan_type) { :SECRET_DETECTION }

  let(:query) do
    graphql_query_for(:security_scan_profile_variables, { scan_type: scan_type }, 'key envVar')
  end

  let(:variables) { graphql_data_at(:security_scan_profile_variables) }

  it 'returns the secret detection variables' do
    post_graphql(query, current_user: user)

    expect(variables.pluck('key')).to eq(%w[
      secureAnalyzersPrefix imageSuffix historicScan logOptions excludedPaths rulesetGitReference
    ])
    expect(variables).to include('key' => 'excludedPaths', 'envVar' => 'SECRET_DETECTION_EXCLUDED_PATHS')
  end

  context 'when the scan type is SAST' do
    let(:scan_type) { :SAST }

    it 'returns the SAST variables' do
      post_graphql(query, current_user: user)

      expect(variables.pluck('envVar')).to include('SAST_EXCLUDED_ANALYZERS', 'GITLAB_ADV_SAST_INCR_SCAN')
    end
  end

  context 'when the scan type has no configuration variables' do
    let(:scan_type) { :DEPENDENCY_SCANNING_POST_PROCESSING }

    it 'returns an empty list' do
      post_graphql(query, current_user: user)

      expect(variables).to eq([])
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_metadata do
    let(:boundary_object) { :instance }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end
end
