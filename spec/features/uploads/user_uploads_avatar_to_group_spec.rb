# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User uploads avatar to group', feature_category: :user_profile do
  let(:user) { create(:user) }
  let(:group) { create(:group) }

  before do
    group.add_owner(user)
    sign_in(user)
  end

  context 'with the HAML form' do
    before do
      stub_feature_flags(group_general_settings_vue: false)
    end

    it 'they see the new avatar' do
      visit edit_group_path(group)
      attach_file(
        'group_avatar',
        Rails.root.join('spec', 'fixtures', 'dk.png'),
        visible: false
      )

      within_testid('general-settings') do
        click_button 'Save changes'
      end

      visit group_path(group)

      avatar_src = page.find(%(img[src*="/uploads/-/system/group/avatar/#{group.id}/dk.png?"]))['src']
      expect(avatar_src).to include("width=")

      # Cheating here to verify something that isn't user-facing, but is important
      expect(group.reload.avatar.file).to exist
    end
  end

  context 'with the Vue form', :js do
    before do
      stub_feature_flags(group_general_settings_vue: true)
    end

    it 'uploads and then removes the avatar' do
      visit edit_group_path(group)

      within_testid('group-general-settings-form') do
        attach_file(
          'group[avatar]',
          Rails.root.join('spec', 'fixtures', 'dk.png'),
          make_visible: true
        )

        click_button 'Save changes'
      end

      expect(page).to have_testid('alert-info')
      expect(group.reload.avatar.url).to eq "/uploads/-/system/group/avatar/#{group.id}/dk.png"

      within_testid('group-general-settings-form') do
        click_button 'Remove avatar'
        click_button 'Save changes'
      end

      expect(page).to have_testid('alert-info')
      expect(page).not_to have_button('Remove avatar')
      expect(group.reload.avatar.url).to be_nil
    end
  end
end
