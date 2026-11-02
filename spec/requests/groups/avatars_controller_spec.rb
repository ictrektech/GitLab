# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::AvatarsController, feature_category: :groups_and_projects do
  include ExternalAuthorizationServiceHelpers

  let(:user)  { create(:user) }
  let(:group) { create(:group, avatar: fixture_file_upload("spec/fixtures/dk.png", "image/png")) }

  before do
    group.add_owner(user)
    sign_in(user)
  end

  it 'removes avatar from DB calling destroy', :aggregate_failures do
    delete group_avatar_path(group)

    group.reload
    expect(group.avatar).not_to be_present
    expect(group).to be_valid
  end

  it 'works when external authorization service is enabled' do
    enable_external_authorization_service_check

    delete group_avatar_path(group)

    expect(response).to have_gitlab_http_status(:found)
  end
end
