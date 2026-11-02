# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/groups/_form' do
  let(:admin) { build_stubbed(:admin) }

  before do
    assign(:group, group)
    allow(view).to receive(:can?).and_return(true)
    allow(view).to receive(:current_user) { admin }
    allow(view).to receive(:visibility_level) { group.visibility_level }
  end

  context 'when sub group is used' do
    let(:root_ancestor) { build_stubbed(:group) }
    let(:group) { build(:group, parent: root_ancestor) }

    it 'does not render shared_runners_minutes_setting' do
      render

      expect(rendered).not_to render_template('namespaces/_shared_runners_minutes_setting')
    end
  end

  context 'when root group is used' do
    let(:group) { build(:group) }

    it 'does not render shared_runners_minutes_setting' do
      render

      expect(rendered).to render_template('namespaces/_shared_runners_minutes_setting')
    end
  end
end
