# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "groups/security/discover/show" do
  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }

  before do
    allow(view).to receive(:current_user).and_return(user)
    assign(:group, group)
    render
  end

  it 'renders vue app root with correct link' do
    expect(rendered).to have_selector('#js-security-discover-app[data-link-main="/-/trial_registrations/new?glm_content=discover-group-security&glm_source=gitlab.com"]')
  end
end
