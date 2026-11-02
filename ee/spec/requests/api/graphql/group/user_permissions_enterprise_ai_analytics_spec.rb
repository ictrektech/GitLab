# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying readEnterpriseAiAnalytics on group user permissions', feature_category: :value_stream_management do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:guest) { create(:user, guest_of: group) }
  let_it_be(:reporter) { create(:user, reporter_of: group) }

  let(:query) do
    graphql_query_for(
      'group',
      { 'fullPath' => group.full_path },
      'userPermissions { readEnterpriseAiAnalytics }'
    )
  end

  where(:role, :ai_analytics_licensed, :expected) do
    :guest    | true  | false
    :reporter | true  | true
    :reporter | false | false
  end

  with_them do
    let(:current_user) { public_send(role) }

    before do
      stub_licensed_features(ai_analytics: ai_analytics_licensed)
    end

    it 'returns the expected permission' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :user_permissions, :read_enterprise_ai_analytics)).to eq(expected)
    end
  end
end
