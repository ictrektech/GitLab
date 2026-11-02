# frozen_string_literal: true

require 'spec_helper'

# Runs against a real Gitaly because the behaviour under test is how a pruning fetch treats refs.
RSpec.describe Import::Sync::Repositories::ReconcileSourceService, 'provider refmap', feature_category: :importers do
  let_it_be(:user) { create(:user) }
  let_it_be(:remote_project) { create(:project, :repository) }

  let(:project) { create(:project, :repository) }
  let(:remote_url) do
    path = Gitlab::GitalyClient::StorageSettings.allow_disk_access { remote_project.repository.path_to_repo }
    "file://#{path}"
  end

  before do
    sha = project.repository.commit('master').id

    %w[github/fork/alice/feature deleted-upstream].each do |name|
      project.repository.add_branch(user, name, sha)
    end
  end

  it 'prunes branches deleted on the provider but keeps the fork branches created only in GitLab' do
    project.repository.fetch_as_mirror(
      remote_url, refmap: described_class::PROVIDER_REFMAP, forced: true, no_tags: true, prune: true
    )

    expect(project.repository.branch_names).to include('master', 'github/fork/alice/feature')
    expect(project.repository.branch_names).not_to include('deleted-upstream')
  end
end
