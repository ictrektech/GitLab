# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Export merge requests', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private) }
  let_it_be(:current_user) { create(:user, developer_of: project) }

  let(:input) { { 'projectPath' => project.full_path, 'approver' => ['approver1'] } }
  let(:mutation) { graphql_mutation(:merge_requests_csv_export, input) }

  it 'schedules the export with approver usernames' do
    expect(IssuableExportCsvWorker)
      .to receive(:perform_async)
      .with(:merge_request, current_user.id, project.id, { approver_usernames: ['approver1'] })

    post_graphql_mutation(mutation, current_user: current_user)

    expect(graphql_errors).to be_nil
  end

  it 'keeps the approver argument on the merge requests resolver' do
    expect(Resolvers::ProjectMergeRequestsResolver.arguments).to include('approver')
  end
end
