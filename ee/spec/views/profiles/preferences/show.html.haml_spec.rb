# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'profiles/preferences/show' do
  before do
    assign(:user, user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(view).to receive(:can?).and_call_original
    stub_feature_flags(enable_hamilton_in_user_preferences: false)
  end

  let(:user) { create_default(:user) }

  context 'security dashboard feature is available' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    it 'renders the group view choice preference' do
      render

      expect(rendered).to have_select('Group overview content')
    end
  end

  context 'security dashboard feature is unavailable' do
    it 'does not render the group view choice preference' do
      render

      expect(rendered).not_to have_select('Group overview content')
    end
  end

  context 'GitLab Duo tab', feature_category: :duo_agent_platform do
    before do
      allow(view).to receive(:can?).with(user, :assign_default_duo_group).and_return(can_assign_duo_group)
      allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(orbit_visible)
    end

    let(:can_assign_duo_group) { false }
    let(:orbit_visible) { false }

    context 'when no GitLab Duo preference is available' do
      it 'does not render the tab' do
        render

        expect(rendered).not_to have_css('a[role="tab"][href="#ai-assistance"]')
        expect(rendered).not_to have_css('.tab-pane#ai-assistance-pane')
      end
    end

    context 'when the default Duo group preference is available' do
      let(:can_assign_duo_group) { true }

      it 'renders the tab with the default group section only' do
        render

        expect(rendered).to have_css('a[role="tab"][href="#ai-assistance"]', text: 'AI assistance')
        expect(rendered).to have_css('.tab-pane#ai-assistance-pane #duo')
        expect(rendered).not_to have_css('#orbit')
      end
    end

    context 'when the Orbit preference is available' do
      let(:orbit_visible) { true }

      it 'renders the tab with the Orbit section only' do
        render

        expect(rendered).to have_css('a[role="tab"][href="#ai-assistance"]', text: 'AI assistance')
        expect(rendered).to have_css('.tab-pane#ai-assistance-pane #orbit[data-testid="orbit-settings-section"]')
        expect(rendered).to have_css('#orbit h2', text: 'GitLab Orbit')
        expect(rendered).not_to have_css('#orbit .gl-badge')
        expect(rendered).not_to have_css('#duo')
      end
    end

    context 'when only the billable Orbit namespace preference is available' do
      let_it_be(:groups) { build_stubbed_list(:group, 2) }

      before do
        allow(view).to receive(:orbit_billable_namespace_candidates).and_return(groups)
      end

      it 'renders the Orbit section with the namespace select only' do
        render

        expect(rendered).to have_css('.tab-pane#ai-assistance-pane #orbit')
        expect(rendered).not_to have_selector('[data-testid="orbit-subsettings"]')

        mount_point = Capybara.string(rendered)
          .find('#orbit-default-group .js-listbox-input[data-name="user[knowledge_graph_governing_namespace_id]"]',
            visible: :all)
        expect(mount_point['data-label']).to eq(_('Default group'))
        expect(Gitlab::Json::SafeParser.parse(mount_point['data-items'])).to match_array(
          groups.map { |group| { 'value' => group.id.to_s, 'text' => group.name } }
        )
      end
    end
  end

  context 'Default Duo namespace assignments', feature_category: :duo_agent_platform do
    context 'when user is not allowed to assign default Duo namespace' do
      before do
        allow(view).to receive(:can?).with(user, :assign_default_duo_group).and_return(false)
      end

      it 'does not have a default Duo group input' do
        render

        expect(rendered).not_to have_css(
          %(.js-listbox-input[data-label="#{_('Default group')}"])
        )
      end
    end

    context 'when user is allowed to assign default Duo namespace' do
      # `freeze: false` is required in this spec: one or more `let_it_be` subjects
      # cannot be frozen by default (deep_freeze traversal failure, a non-AR
      # subject, or an in-memory mutation that survives reload/refind). Do not
      # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
      # (see gitlab-org/gitlab#602925).
      let_it_be(:namespaces, freeze: false) do
        list = create_list(:namespace, 2) # rubocop:disable RSpec/FactoryBot/AvoidCreate -- DB query required
        Namespace.where(id: list)
      end

      let!(:user_preference) do
        user.user_preference.tap { |p| allow(user).to receive(:user_preference).and_return(p) }
      end

      let(:mount_point) do
        Capybara.string(rendered).find(%(.js-listbox-input[data-name="user[duo_default_namespace_id]"]),
          visible: :all)
      end

      before do
        allow(view).to receive(:can?).with(user, :assign_default_duo_group).and_return(true)
        allow(user_preference).to receive(:duo_default_namespace_candidates).and_return(namespaces)
      end

      context 'with no namespace selected' do
        it 'renders the listbox mount point with placeholder text and candidate items' do
          render

          expect(mount_point['data-label']).to eq(_('Default group'))
          expect(mount_point['data-default-toggle-text']).to eq(_('Select a group'))
          expect(Gitlab::Json::SafeParser.parse(mount_point['data-items'])).to match_array(
            namespaces.map { |namespace| { 'value' => namespace.id.to_s, 'text' => namespace.name } }
          )
        end
      end

      context 'with no candidate groups available' do
        before do
          allow(user_preference).to receive(:duo_default_namespace_candidates).and_return(Namespace.none)
        end

        it 'renders an empty state instead of the listbox' do
          render

          expect(rendered).not_to have_css(
            %(.js-listbox-input[data-name="user[duo_default_namespace_id]"]), visible: :all
          )
          expect(rendered).not_to have_field('user[duo_default_namespace_id]')
          expect(rendered).to have_css('[data-testid="duo-default-group-empty"]',
            text: s_("Profiles|You don't have access to any groups eligible for GitLab Duo."))
        end
      end

      context 'with default already selected' do
        before do
          allow(user_preference).to receive(:duo_default_namespace_with_fallback).and_return(namespaces.first)
        end

        it 'renders the listbox mount point with the selected value' do
          render

          expect(mount_point['data-value']).to eq(namespaces.first.id.to_s)
        end
      end
    end
  end

  context 'Orbit settings', feature_category: :duo_agent_platform do
    context 'when the orbit preferences section is not visible' do
      before do
        allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(false)
      end

      it 'does not render the orbit settings section' do
        render

        expect(rendered).not_to have_selector('[data-testid="orbit-settings-section"]')
      end
    end

    context 'when the orbit preferences section is visible' do
      before do
        allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(true)
      end

      it 'renders the four subsettings without a whole-feature toggle' do
        render

        expect(rendered).to have_selector('[data-testid="orbit-settings-section"]')
        expect(rendered).to have_selector('[data-testid="orbit-subsettings"]')
        expect(rendered).not_to have_field('user[orbit_enabled]', type: 'checkbox')
        expect(rendered).to have_field('user[orbit_agent_enabled]', type: 'checkbox')
        expect(rendered).to have_field('user[orbit_agentic_chat_enabled]', type: 'checkbox')
        expect(rendered).to have_field('user[orbit_other_foundational_agents_enabled]', type: 'checkbox')
        expect(rendered).to have_field('user[orbit_custom_agents_enabled]', type: 'checkbox')
      end

      it 'checks every subsetting by default' do
        user.user_preference.update!(orbit_settings: {})

        render

        expect(rendered).to have_checked_field('user[orbit_agent_enabled]')
        expect(rendered).to have_checked_field('user[orbit_agentic_chat_enabled]')
        expect(rendered).to have_checked_field('user[orbit_other_foundational_agents_enabled]')
        expect(rendered).to have_checked_field('user[orbit_custom_agents_enabled]')
      end

      it 'reflects a stored subsetting opt-out' do
        user.user_preference.update!(orbit_settings: { 'orbit_agent_enabled' => false })

        render

        expect(rendered).to have_unchecked_field('user[orbit_agent_enabled]')
        expect(rendered).to have_checked_field('user[orbit_agentic_chat_enabled]')
      end
    end
  end

  context 'Code Suggestions self-assignment', :saas, feature_category: :code_suggestions do
    context 'when the feature is available' do
      before do
        stub_feature_flags(enable_hamilton_in_user_preferences: user)
      end

      it 'renders the code suggestions preference' do
        render

        expect(rendered).to render_template('profiles/preferences/_code_suggestions_settings_self_assignment')
        field_text = s_('Preferences|Code Suggestions')
        expect(rendered).to have_content(field_text)
      end
    end

    context 'when the feature is not available' do
      it 'does not render the code suggestions preference' do
        render

        expect(rendered).not_to render_template('profiles/preferences/_code_suggestions_settings_self_assignment')
        field_text = s_('Preferences|Code Suggestions')
        expect(rendered).not_to have_content(field_text)
      end
    end
  end
end
