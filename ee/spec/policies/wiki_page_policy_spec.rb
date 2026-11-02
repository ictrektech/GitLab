# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WikiPagePolicy, feature_category: :wiki do
  let_it_be(:group) { create(:group) }

  it 'delegates a group wiki page to the group policy' do
    wiki_page = build(:wiki_page, container: group)

    expect(described_class.new(nil, wiki_page)).to delegate_to(GroupPolicy)
  end
end
