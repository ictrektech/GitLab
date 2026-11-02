# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::Organizations::Menus::ManageMenu, feature_category: :navigation do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:member) { create(:user) }

  let(:user) { owner }
  let(:context) { Sidebars::Context.new(current_user: user, container: organization) }
  let(:menu) { described_class.new(context) }

  subject(:access_item) { menu.renderable_items.find { |item| item.item_id == :organization_access } }

  before_all do
    create(:organization_user, :owner, organization: organization, user: owner)
    create(:organization_user, organization: organization, user: member)
  end

  describe 'the Organization access item' do
    it 'links to the organization access page', :aggregate_failures do
      expect(access_item).to be_present
      expect(access_item.link).to eq(Gitlab::Routing.url_helpers.access_organization_path(organization))
    end

    context 'when the `organization_access_ui` feature flag is disabled' do
      before do
        stub_feature_flags(organization_access_ui: false)
      end

      it 'does not show the item' do
        expect(access_item).to be_nil
      end
    end

    context 'when the user is a member without the owner role' do
      let(:user) { member }

      it 'does not show the item' do
        expect(access_item).to be_nil
      end
    end
  end
end
