# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::UnsubscribesController, feature_category: :user_profile do
  let_it_be_with_reload(:user) { create(:user, email: 'me@example.com') }

  describe "show" do
    it "responds with success" do
      get unsubscribe_path(Base64.urlsafe_encode64('me@example.com'))

      expect(response).to have_gitlab_http_status(:ok)
    end

    it "behaves the same if email address isn't known in the system" do
      get unsubscribe_path(Base64.urlsafe_encode64('i@dont_exists.com'))

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe "create" do
    it "unsubscribes the connected user" do
      post unsubscribe_path(Base64.urlsafe_encode64('me@example.com'))

      expect(user.reload.admin_email_unsubscribed_at).to be_present
    end

    # Don't tell if the email does not exists
    it "behaves the same if email address isn't known in the system" do
      post unsubscribe_path(Base64.urlsafe_encode64('i@dont_exists.com'))

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
