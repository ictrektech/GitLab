# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group > User views empty wiki', feature_category: :wiki do
  include WikiHelpers

  let_it_be(:user) { create(:user) }

  let(:wiki) { create(:group_wiki, group: group) }
  let(:element) { page.find('.gl-empty-state[data-testid="wiki-empty-state"]') }
  let(:confluence_link) { 'Enable the Confluence Wiki integration' }

  before do
    stub_group_wikis(true)
  end

  shared_examples 'wiki is not found' do |message|
    it 'shows an error message' do
      visit wiki_path(wiki)

      expect(page).to have_content(message)
    end
  end

  # rubocop:disable RSpec/AvoidConditionalStatements -- legacy conditionals, relocated as-is
  shared_examples 'empty wiki message' do |writable: false|
    # This mirrors the logic in:
    # - app/views/shared/empty_states/_wikis.html.haml
    # - WikiHelper#wiki_empty_state_messages
    it 'shows the empty state message with the expected elements', :js do
      visit wiki_path(wiki)

      if writable
        expect(element).to have_content("Get started with wikis")
      else
        expect(element).to have_content("This wiki doesn't have any content yet")
      end

      expect(element).to have_no_link(confluence_link)

      if writable
        element.click_link 'Create your first page'

        expect(page).to have_button('Create page')
      else
        expect(element).to have_no_link('Create your first page')
      end
    end
  end
  # rubocop:enable RSpec/AvoidConditionalStatements

  context 'when group is public' do
    let(:group) { create(:group, :public) }

    it_behaves_like 'empty wiki message'

    context 'and user is logged in' do
      before do
        sign_in(user)
      end

      context 'and user is not a member' do
        it_behaves_like 'empty wiki message'
      end

      context 'and user is a member' do
        before do
          group.add_developer(user)
        end

        it_behaves_like 'empty wiki message', writable: true
      end
    end
  end

  context 'when group is private' do
    let(:group) { create(:group, :private) }

    it_behaves_like 'wiki is not found', 'Sign in or sign up'

    context 'and user is logged in' do
      before do
        sign_in(user)
      end

      context 'and user is not a member' do
        it_behaves_like 'wiki is not found', 'Page not found'
      end

      context 'and user is a member' do
        before do
          group.add_developer(user)
        end

        it_behaves_like 'empty wiki message', writable: true
      end
    end
  end
end
