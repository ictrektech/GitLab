# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.mergeRequests', feature_category: :value_stream_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be(:merge_requests) { create_list(:merge_request, 2, :unique_branches, source_project: project) }

  let(:query) do
    <<~GQL
    query($path: ID!) {
      group(fullPath: $path) {
        mergeRequests { timeLimitedCount }
      }
    }
    GQL
  end

  let(:time_limited_count) { graphql_data_at(:group, :merge_requests, :time_limited_count) }

  def run_query
    post_graphql(query, current_user: user, variables: { path: group.full_path })
  end

  describe 'timeLimitedCount' do
    context 'when the time limit is available', :saas_siphon_clickhouse_analytics do
      it 'counts within the fast read statement timeout' do
        expect(ApplicationRecord).to receive(:with_fast_read_statement_timeout).and_call_original

        run_query

        expect(time_limited_count).to eq(2)
      end

      context 'when the count exceeds the time limit' do
        before do
          allow(ApplicationRecord).to receive(:with_fast_read_statement_timeout)
            .and_raise(ActiveRecord::QueryCanceled)
        end

        it 'returns null and logs the timeout with the group', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
            an_instance_of(ActiveRecord::QueryCanceled),
            { Labkit::Fields::ADDITIONAL_DETAILS => 'merge_request_connection_time_limited_count',
              Labkit::Fields::GL_NAMESPACE_ID => group.id }
          )

          run_query

          expect(graphql_errors).to be_nil
          expect(time_limited_count).to be_nil
        end

        context 'when counting a project' do
          let(:query) do
            <<~GQL
            query($path: ID!) {
              project(fullPath: $path) {
                mergeRequests { timeLimitedCount }
              }
            }
            GQL
          end

          it 'logs the timeout with the project', :aggregate_failures do
            expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
              an_instance_of(ActiveRecord::QueryCanceled),
              { Labkit::Fields::ADDITIONAL_DETAILS => 'merge_request_connection_time_limited_count',
                Labkit::Fields::GL_PROJECT_ID => project.id }
            )

            post_graphql(query, current_user: user, variables: { path: project.full_path })

            expect(graphql_data_at(:project, :merge_requests, :time_limited_count)).to be_nil
          end
        end

        context 'when counting for a parent that is neither a group nor a project' do
          let(:query) do
            <<~GQL
            query {
              currentUser {
                authoredMergeRequests { timeLimitedCount }
              }
            }
            GQL
          end

          it 'logs the timeout without a parent ID', :aggregate_failures do
            expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
              an_instance_of(ActiveRecord::QueryCanceled),
              { Labkit::Fields::ADDITIONAL_DETAILS => 'merge_request_connection_time_limited_count' }
            )

            post_graphql(query, current_user: user)

            expect(graphql_data_at(:current_user, :authored_merge_requests, :time_limited_count)).to be_nil
          end
        end
      end
    end

    context 'when the time limit is not available' do
      before do
        stub_saas_features(siphon_clickhouse_analytics: false)
      end

      it 'returns the exact count without a time limit' do
        expect(ApplicationRecord).not_to receive(:with_fast_read_statement_timeout)

        run_query

        expect(time_limited_count).to eq(2)
      end

      context 'when the count hits the statement timeout' do
        before do
          allow_next_instance_of(Types::MergeRequestConnectionType) do |connection_type|
            allow(connection_type).to receive(:count).and_raise(ActiveRecord::QueryCanceled)
          end
        end

        it 'fails the request instead of returning null', :aggregate_failures do
          expect(Gitlab::ErrorTracking).not_to receive(:log_exception)

          run_query

          expect(response).to have_gitlab_http_status(:service_unavailable)
          expect(graphql_errors).to contain_exactly(
            a_hash_including('message' => a_string_including('Request timed out'))
          )
        end
      end
    end
  end
end
