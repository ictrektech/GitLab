# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "projects/security/discover/show" do
  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project) }

  before do
    allow(view).to receive(:current_user).and_return(user)
    assign(:project, project)
    render
  end

  it 'renders vue app root with correct link' do
    expect(rendered).to have_selector('#js-security-discover-app[data-link-main="/-/trial_registrations/new?glm_content=discover-project-security&glm_source=gitlab.com"]')
  end
end
