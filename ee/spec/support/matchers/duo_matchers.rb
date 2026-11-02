# frozen_string_literal: true

RSpec::Matchers.define :redirect_to_sign_in do
  match do |response|
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to include('Sign in or sign up before continuing')
  end
end
