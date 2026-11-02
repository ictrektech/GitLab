# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group > Settings > GitLab Duo > Agent and flow setup', :js, :saas,
  feature_category: :ai_abstraction_layer do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group, owners: user) }

  before_all do
    create(:gitlab_subscription, :ultimate, namespace: group)
    create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
  end

  before do
    stub_licensed_features(code_suggestions: true, ai_features: true)
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_request(:get, "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions")
      .to_return(status: 200, body: { 'models' => [], 'unit_primitives' => [] }.to_json,
        headers: { 'Content-Type' => 'application/json' })
    group.namespace_settings.update!(duo_core_features_enabled: false)
    sign_in(user)

    visit group_settings_gitlab_duo_configuration_index_path(group)
  end

  it 'saves a setting changed from the readiness card', :aggregate_failures do
    expect(page).to have_css('h1', text: 'Run GitLab Duo agents and flows in this group')
    expect(page).to have_css('[data-testid="readiness-section-title"]', text: 'Agent and flow setup')
    expect(page).to be_axe_clean.within_testid('duo-group-readiness-card').skipping(:'link-in-text-block')

    within_testid('seatless-access-row') do
      find('[data-testid="seatless-access-toggle"] button').click
    end

    click_button 'Save changes'

    expect(page).to have_content('Group was successfully updated')
    expect(group.reload.namespace_settings.duo_core_features_enabled).to be(true)
  end

  context 'when flow execution is off' do
    before do
      group.namespace_settings.update!(duo_remote_flows_availability: false)

      visit group_settings_gitlab_duo_configuration_index_path(group)
    end

    it 'turns flow execution on from the card', :aggregate_failures do
      within_testid('flow-execution-row') do
        find('[data-testid="flow-execution-toggle"] button').click
      end

      click_button 'Save changes'

      expect(page).to have_content('Group was successfully updated')
      expect(group.reload.namespace_settings.duo_remote_flows_enabled).to be(true)
    end

    it 'keeps the muted flow toggles focusable and points them at the note', :aggregate_failures do
      toggle = find('[data-testid="custom-flows-toggle"] button')

      expect(toggle).not_to be_disabled
      expect(toggle['aria-disabled']).to eq('true')
      expect(page).to have_css("##{toggle['aria-describedby']}",
        text: 'Turn on Flow execution to change Foundational flows and Custom flows.')
    end
  end

  context 'when the feature flag is off' do
    before do
      stub_feature_flags(duo_group_agent_readiness_settings: false)

      visit group_settings_gitlab_duo_configuration_index_path(group)
    end

    it 'renders the existing configuration page' do
      expect(page).to have_css('h1', text: 'Configuration')
      expect(page).to have_no_testid('duo-group-readiness-card')
    end
  end
end
