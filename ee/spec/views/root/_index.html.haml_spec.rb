# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'root/index.html.haml', feature_category: :onboarding do
  let_it_be(:mock_activity_path) { "activity_path" }
  let_it_be(:groups_requiring_reauth) { create_list(:group, 1) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- persisted record required

  before do
    @homepage_app_data = { activity_path: mock_activity_path }
    allow(view).to receive_messages(user_groups_requiring_reauth: groups_requiring_reauth)
    render
  end

  it 'renders a group SAML re-authentication banner and button' do
    expect(rendered).to have_text(s_('GroupSAML|Group SAML single sign-on session expired'))
    expect(rendered).to have_text(format(s_('GroupSAML|Re-authenticate %{group}'),
      group: groups_requiring_reauth[0].path))
  end
end
