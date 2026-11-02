# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'layouts/application', :with_current_organization do
  let_it_be(:user) { create(:user) }

  before do
    allow(view).to receive_messages(
      session: {},
      user_signed_in?: true,
      current_user: user,
      current_user_mode: Gitlab::Auth::CurrentUserMode.new(user)
    )
  end

  it_behaves_like 'a layout which reflects the application theme setting'
  it_behaves_like 'a layout which reflects the preferred language'
end
