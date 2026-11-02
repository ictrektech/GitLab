# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/groups/_group.html.haml', feature_category: :groups_and_projects do
  let(:group) { build_stubbed(:group, description: description) }

  before do
    allow(group).to receive_messages(
      non_archived_projects: Array.new(3),
      non_invite_group_members: Array.new(5)
    )

    render partial: 'shared/groups/group', locals: { group: group, user: nil }
  end

  context 'with a description' do
    let(:description) { 'A long group description that should wrap across multiple lines' }

    it 'renders the description' do
      expect(rendered).to have_css('.description', text: description)
    end

    it 'renders a single set of stats', :aggregate_failures do
      expect(rendered).to have_css('.stats', count: 1)
      expect(rendered).to have_css('.stats [title="Projects"]', text: '3', count: 1)
      expect(rendered).to have_css('.stats [title="Users"]', text: '5', count: 1)
      expect(rendered).to have_css('.stats .visibility-icon', count: 1)
    end
  end

  context 'without a description' do
    let(:description) { nil }

    it 'does not render a description' do
      expect(rendered).not_to have_css('.description')
    end
  end
end
