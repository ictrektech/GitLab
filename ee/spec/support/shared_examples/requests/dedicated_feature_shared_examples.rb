# frozen_string_literal: true

RSpec.shared_examples 'pushes dedicated feature in request' do |feature_name|
  it "pushes #{feature_name} as Dedicated feature" do
    stub_application_setting(gitlab_dedicated_instance: true)

    subject

    expect(response.body).to match(/gon\.dedicated_features=\{[^}]*"#{feature_name.to_s.camelize(:lower)}":true/)
  end
end
