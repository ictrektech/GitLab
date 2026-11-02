# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group > Settings > GitLab Duo > Group runner row', :js, :saas,
  feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group, owners: user) }

  let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(group) }

  let(:not_connected_copy) { s_('DuoAgentPlatform|Not connected. Flows run as CI/CD jobs and require a runner.') }
  let(:connected_copy) { s_('DuoAgentPlatform|Connected. A runner is available and picking up jobs.') }
  let(:check_again_label) { s_('DuoAgentPlatform|Check again') }

  # The runner fields are authorized with :duo_workflow, so the owner needs a Duo
  # seat and the group needs the Agent Platform on; the card itself does not.
  before_all do
    create(:gitlab_subscription, :ultimate, namespace: group)
    add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
    create(:gitlab_subscription_user_add_on_assignment, add_on_purchase: add_on_purchase, user: user)
    group.namespace_settings.update!(duo_features_enabled: true)
    group.ai_settings.update!(duo_agent_platform_enabled: true)
  end

  before do
    stub_licensed_features(code_suggestions: true, ai_features: true)
    stub_saas_features(gitlab_com_subscriptions: true)
    # Model selection would otherwise fetch the model catalog from the AI gateway.
    allow(::Ai::ModelSelection::FetchModelDefinitionsService).to receive(:new).and_return(
      instance_double(::Ai::ModelSelection::FetchModelDefinitionsService,
        execute: ServiceResponse.success(payload: { 'models' => [], 'unit_primitives' => [] }))
    )
    # The seat check would otherwise call CustomersDot.
    allow_next_instance_of(::Ai::UsageQuotaService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success)
    end
    # Stub the entitlement seam so the real :duo_workflow policy grant is exercised.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    sign_in(user)
  end

  it 'tells a root group owner to register a runner while none can pick up Duo workloads' do
    visit group_settings_gitlab_duo_configuration_index_path(group)

    within_testid('runner-row') do
      expect(page).to have_content(not_connected_copy)
      expect(page).to have_link(
        s_('DuoAgentPlatform|How to configure'),
        href: help_page_path('user/duo_agent_platform/flows/execution/_index.md',
          anchor: 'configure-runners-to-execute-flows')
      )
      expect(page).to have_button(check_again_label)
    end
  end

  it 'updates to connected when "Check again" finds a newly registered runner' do
    visit group_settings_gitlab_duo_configuration_index_path(group)

    within_testid('runner-row') do
      expect(page).to have_content(not_connected_copy)
    end

    runner = create(:ci_runner, :group, :online, groups: [group], tag_list: [workload_tag])
    create(:ci_runner_machine, runner: runner, executor_type: :docker)

    within_testid('runner-row') do
      click_button check_again_label

      expect(page).to have_content(connected_copy)
    end
  end

  context 'when a Duo-tagged group runner is online' do
    before do
      runner = create(:ci_runner, :group, :online, groups: [group], tag_list: [workload_tag])
      create(:ci_runner_machine, runner: runner, executor_type: :docker)
    end

    it 'reports the runner and links to the group runners page' do
      visit group_settings_gitlab_duo_configuration_index_path(group)

      within_testid('runner-row') do
        expect(page).to have_content(connected_copy)
        expect(page).to have_link(
          s_('DuoAgentPlatform|View runners'),
          href: "#{group_runners_path(group)}?runner_type=GROUP_TYPE"
        )
      end
    end
  end
end
