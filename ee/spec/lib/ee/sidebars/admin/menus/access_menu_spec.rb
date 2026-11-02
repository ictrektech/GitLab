# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::Admin::Menus::AccessMenu, feature_category: :navigation do
  let(:user) { build_stubbed(:user, :admin) }
  let(:context) { Sidebars::Context.new(current_user: user, container: nil) }
  let(:menu) { described_class.new(context) }

  describe 'Credentials menu item', :enable_admin_mode do
    subject(:item_ids) { menu.renderable_items.map(&:item_id) }

    before do
      stub_licensed_features(credentials_inventory: licensed)
    end

    context 'when credentials inventory is licensed' do
      let(:licensed) { true }

      it 'is rendered before deploy keys' do
        expect(item_ids.first(2)).to eq([:credentials, :deploy_keys])
      end

      it 'links to the credentials inventory' do
        item = menu.renderable_items.find { |e| e.item_id == :credentials }

        expect(item.title).to eq(s_('Admin|Credentials'))
        expect(item.link).to eq('/admin/credentials')
        expect(item.active_routes).to eq(controller: :credentials)
      end

      it 'uses the credentials link as the menu link' do
        expect(menu.link).to eq('/admin/credentials')
      end
    end

    context 'when credentials inventory is not licensed' do
      let(:licensed) { false }

      it { is_expected.not_to include(:credentials) }

      it 'falls back to the deploy keys link' do
        expect(menu.link).to eq('/admin/deploy_keys')
      end
    end
  end
end
