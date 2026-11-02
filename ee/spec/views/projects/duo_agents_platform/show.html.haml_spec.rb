# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/duo_agents_platform/show', feature_category: :duo_agent_platform do
  let_it_be(:project) { build_stubbed(:project) }

  before do
    assign(:project, project)
    allow(view).to receive(:project_automate_agent_sessions_path).with(project).and_return('/test-project/-/automate')

    # Mock credits_available? to avoid HTTP requests to subscription portal
    allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive(:credits_available?).and_return(true)
    end
  end

  context 'when identity verification is not required' do
    it 'renders the agents platform page container' do
      render

      expect(rendered).to have_css('#js-duo-agents-platform-page')
      expect(rendered).not_to have_css('.js-duo-agents-platform-verification-alert')
    end

    it 'calls the duo agents platform helper' do
      expect(view).to receive(:duo_agents_platform_data).with(project).and_call_original
      render
    end
  end

  describe 'panel header' do
    let_it_be(:user) { build_stubbed(:user) }

    before do
      allow(view).to receive_messages(current_user: user, duo_agents_platform_data: {})
    end

    it 'is forced when duo_automations is enabled for the current user' do
      stub_feature_flags(duo_automations: user)

      render

      expect(view.instance_variable_get(:@force_show_panel_header)).to be(true)
    end

    it 'is not forced when duo_automations is enabled for another user' do
      stub_feature_flags(duo_automations: build_stubbed(:user))

      render

      expect(view.instance_variable_get(:@force_show_panel_header)).to be_nil
    end
  end

  context 'when identity verification is required' do
    before do
      allow(view).to receive(:dap_identity_verification_required?).with(project).and_return(true)
      allow(view).to receive(:duo_agents_platform_identity_verification_data).with(project).and_return({})
    end

    it 'renders the identity verification alert instead of the page' do
      render

      expect(rendered).to have_css('.js-duo-agents-platform-verification-alert')
      expect(rendered).not_to have_css('#js-duo-agents-platform-page')
    end

    it 'passes the identity verification data to the alert' do
      expect(view).to receive(:duo_agents_platform_identity_verification_data).with(project)
      render
    end
  end
end
