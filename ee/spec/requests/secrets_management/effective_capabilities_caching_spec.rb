# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Effective capabilities caching', :use_clean_rails_memory_store_caching,
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:reporter) { create(:user, :with_namespace, reporter_of: project) }
  let_it_be_with_reload(:secrets_manager) { create(:project_secrets_manager, project: project) }

  let(:client) { instance_double(SecretsManagement::SecretsManagerClient) }
  let(:data_path) { secrets_manager.ci_full_path('*') }
  let(:detailed_metadata_path) { secrets_manager.detailed_metadata_path('*') }

  let(:query) do
    graphql_query_for(
      'projectSecretsManager',
      { project_path: project.full_path },
      <<~FIELDS
        userPermissions {
          readMetadata
          createSecrets
          updateSecrets
          deleteSecrets
        }
      FIELDS
    )
  end

  before do
    secrets_manager.activate!
    stub_licensed_features(native_secrets_management: true)
    stub_secrets_manager_entitlement(state: :paid)
    enroll_instance_in_secrets_manager

    allow_next_instances_of(SecretsManagement::UserPermissions::ProjectEffectiveCapabilitiesService, nil) do |service|
      allow(service).to receive(:user_scoped_client).and_return(client)
    end
  end

  # Every secrets page load sends the status query, which selects userPermissions,
  # so without the cache each reload would pay its own three OpenBao round trips.
  it 'queries OpenBao once across separate GraphQL requests', :aggregate_failures do
    expect(client).to receive(:capabilities_self).once
      .with(paths: [data_path, detailed_metadata_path])
      .and_return({ "data" => { data_path => %w[create update], detailed_metadata_path => %w[list] } })

    post_graphql(query, current_user: reporter)
    post_graphql(query, current_user: reporter)

    expect(graphql_data_at(:project_secrets_manager, :user_permissions)).to eq(
      'readMetadata' => true,
      'createSecrets' => true,
      'updateSecrets' => true,
      'deleteSecrets' => false
    )
  end
end
