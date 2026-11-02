# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/security/inventory/show.html.haml', feature_category: :security_asset_inventories do
  let(:group) { build_stubbed(:group) }

  before do
    assign(:group, group)
    allow(view).to receive(:group_level_security_inventory_data).with(group).and_return({})
  end

  it 'renders the placeholder for the UI component' do
    render

    expect(rendered).to have_selector('#js-group-security-inventory')
  end

  it 'sets the page to fluid layout' do
    render

    expect(view.instance_variable_get(:@force_fluid_layout)).to be(true)
  end
end
