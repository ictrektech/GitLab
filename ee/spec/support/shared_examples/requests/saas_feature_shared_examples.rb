# frozen_string_literal: true

RSpec.shared_examples 'pushes saas feature in request' do |feature_name|
  it "pushes #{feature_name} as SaaS feature" do
    stub_saas_features(feature_name => true)

    subject

    expect(response.body).to match(/gon\.saas_features=\{[^}]*"#{feature_name.to_s.camelize(:lower)}":true/)
  end
end
