# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::Topics::AvatarsController, :enable_admin_mode, feature_category: :groups_and_projects do
  let_it_be(:user) { create(:admin) }
  # A shared topic would lose its avatar file across examples, as removal deletes it from disk
  let(:topic) { create(:topic, avatar: fixture_file_upload("spec/fixtures/dk.png")) }

  before do
    sign_in(user)
  end

  it 'removes avatar from DB by calling destroy', :aggregate_failures do
    delete admin_topic_avatar_path(topic)

    expect(response).to redirect_to(edit_admin_topic_path(topic))
    expect(topic.reload.avatar.present?).to be_falsey
    expect(topic).to be_valid
  end

  context 'when the user is not an admin' do
    let_it_be(:user) { create(:user) }

    it 'returns not found and keeps the avatar', :aggregate_failures do
      delete admin_topic_avatar_path(topic)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(topic.reload.avatar.present?).to be_truthy
    end
  end
end
