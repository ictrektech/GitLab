# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project > User views empty wiki', feature_category: :wiki do
  let_it_be(:auditor) { create(:user, auditor: true) }
  let_it_be(:project) { create(:project, :private) }
  let_it_be(:wiki) { create(:project_wiki, project: project) }

  let(:element) { page.find('.gl-empty-state[data-testid="wiki-empty-state"]') }

  shared_examples 'read-only empty wiki message' do
    it 'shows the read-only empty state message', :js do
      visit wiki_path(wiki)

      expect(element).to have_content("This wiki doesn't have any content yet")
      expect(element).to have_no_link('Enable the Confluence Wiki integration')
      expect(element).to have_no_link('Create your first page')
    end
  end

  context 'when signed in user is an Auditor' do
    before do
      sign_in(auditor)
    end

    context 'when user is not a member of the project' do
      it_behaves_like 'read-only empty wiki message'
    end

    context 'when user is a member of the project' do
      before do
        project.add_guest(auditor)
      end

      it_behaves_like 'read-only empty wiki message'
    end
  end
end
