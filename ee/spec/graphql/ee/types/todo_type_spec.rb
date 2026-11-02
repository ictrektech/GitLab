# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['Todo'], feature_category: :notifications do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project, developers: current_user) }
  let_it_be(:note) { create(:note, project: project) }

  context 'when the target can no longer be loaded' do
    let_it_be(:todo) { create(:on_commit_todo, user: current_user, project: project, note: note) }

    # The policy only lets readable to-dos through, but a commit target is
    # looked up again on every call and resolves to nil if that lookup fails.
    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    it 'hides the target-derived contents' do
      ghost = ::Users::Internal.in_organization(project.organization_id).ghost

      expect(todo.target).to be_nil
      expect(resolve_field(:body, todo, current_user: current_user)).to eq('')
      expect(resolve_field(:note, todo, current_user: current_user)).to be_nil
      expect(resolve_field(:author, todo, current_user: current_user)).to eq(ghost)
    end
  end
end
