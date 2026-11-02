import { GlAvatar, GlIcon, GlLink, GlSprintf, GlToken } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { MountingPortal } from 'portal-vue';
import { resetHTMLFixture, setHTMLFixture } from 'helpers/fixtures';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import AutomationDetailsPanel from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_details_panel.vue';
import AutomationRecentRuns from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_recent_runs.vue';
import AutomationRunStats from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_run_stats.vue';
import {
  FLOW_TRIGGER_MODE_SCHEDULE,
  FLOW_TRIGGER_TYPE_SCHEDULE,
  SCHEDULE_FREQUENCY_DAILY,
} from 'ee/ai/duo_agents_platform/constants';
import getProjectServiceAccountRoles from 'ee/ai/duo_agents_platform/graphql/queries/get_project_service_account_roles.query.graphql';
import { mockFlowTriggerFactory, mockServiceAccountRolesResponse } from '../../mocks';

Vue.use(VueApollo);
jest.mock('~/sentry/sentry_browser_wrapper');

describe('AutomationDetailsPanel', () => {
  let wrapper;

  const serviceAccount = {
    id: 'gid://gitlab/User/501',
    name: 'Flow service account',
    avatarUrl: 'https://example.com/sa.png',
    webPath: '/flow-sa',
  };
  const rolesHandler = jest.fn();
  const timezoneData = [
    { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
  ];

  const createComponent = ({
    automation = mockFlowTriggerFactory({ user: serviceAccount }),
  } = {}) => {
    wrapper = shallowMountExtended(AutomationDetailsPanel, {
      apolloProvider: createMockApollo([[getProjectServiceAccountRoles, rolesHandler]]),
      propsData: { automation },
      provide: { projectPath: 'my-group/my-project', timezoneData },
      stubs: {
        MountingPortal: stubComponent(MountingPortal, {
          props: { mountTo: String, append: Boolean },
        }),
        DynamicPanel: stubComponent(DynamicPanel, { template: '<div><slot></slot></div>' }),
        DetailLayout: stubComponent(DetailLayout, { template: '<div><slot></slot></div>' }),
        GlSprintf,
      },
    });
  };

  const findPortal = () => wrapper.findComponent(MountingPortal);
  const findPanel = () => wrapper.findComponent(DynamicPanel);
  const findDetailLayout = () => wrapper.findComponent(DetailLayout);
  const findConditions = () => wrapper.findByTestId('automation-conditions');
  const findConditionTokens = () => findConditions().findAllComponents(GlToken);
  const findSchedule = () => wrapper.findByTestId('automation-schedule');
  const findScheduleBetaBadge = () => wrapper.findByTestId('automation-schedule-beta-badge');
  const findSource = () => wrapper.findByTestId('automation-source');
  const findServiceAccount = () => wrapper.findByTestId('automation-service-account');
  const pressKey = (key = 'Escape') =>
    document.dispatchEvent(new KeyboardEvent('keydown', { key }));

  beforeEach(() => {
    rolesHandler.mockResolvedValue(mockServiceAccountRolesResponse);
  });

  describe('default', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders into the contextual panel portal', () => {
      expect(findPortal().props()).toMatchObject({
        mountTo: '#contextual-panel-portal',
        append: true,
      });
    });

    it('renders the panel header and the automation description as the heading', () => {
      expect(findPanel().props('header')).toBe('Automation details');
      expect(findDetailLayout().props()).toMatchObject({
        heading: 'Test trigger',
        showSidebar: false,
      });
    });

    it('renders the run statistics of the automation', () => {
      expect(wrapper.findComponent(AutomationRunStats).props('automationId')).toBe(
        mockFlowTriggerFactory().id,
      );
    });

    it('renders the recent runs of the automation', () => {
      expect(wrapper.findComponent(AutomationRecentRuns).props('automationId')).toBe(
        mockFlowTriggerFactory().id,
      );
    });

    it('renders the conditions without a schedule', () => {
      expect(findConditionTokens().wrappers.map((token) => token.text())).toEqual([
        'Mention',
        'Assign',
      ]);
      expect(findSchedule().exists()).toBe(false);
      expect(findScheduleBetaBadge().exists()).toBe(false);
    });

    it('links the source to the config file', () => {
      const link = findSource().findComponent(GlLink);

      expect(findSource().findComponent(GlIcon).props('name')).toBe('doc-text');
      expect(link.attributes('href')).toBe('https://example.com/config/test.yml');
      expect(link.text()).toBe('test.yml');
    });

    it('fetches the role of the service account and renders it with the account', () => {
      const link = findServiceAccount().findComponent(GlLink);

      expect(rolesHandler).toHaveBeenCalledWith({
        fullPath: 'my-group/my-project',
        ids: ['gid://gitlab/User/501'],
      });
      expect(findServiceAccount().text()).toMatchInterpolatedText(
        'Flow service account runs as Developer',
      );
      expect(link.attributes('href')).toBe('/flow-sa');
      expect(link.findComponent(GlAvatar).attributes()).toMatchObject({
        src: 'https://example.com/sa.png',
        alt: '',
      });
    });

    it('emits close when the panel closes', () => {
      findPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('without event types', () => {
    beforeEach(() => {
      createComponent({ automation: mockFlowTriggerFactory({ eventTypes: [] }) });
    });

    it('does not render the conditions', () => {
      expect(findConditions().exists()).toBe(false);
    });
  });

  describe('with a schedule', () => {
    it.each`
      description           | timezone              | expected
      ${'a known timezone'} | ${'America/New_York'} | ${'Daily at 09:00 [UTC-5] Eastern Time (US & Canada)'}
      ${'an unknown one'}   | ${'Etc/UTC'}          | ${'Daily at 09:00 Etc/UTC'}
    `(
      'renders a plain schedule condition and the schedule with $description in its own row',
      ({ timezone, expected }) => {
        createComponent({
          automation: mockFlowTriggerFactory({
            eventTypes: [FLOW_TRIGGER_TYPE_SCHEDULE.valueInt],
            filter: {
              [FLOW_TRIGGER_MODE_SCHEDULE]: {
                frequency: SCHEDULE_FREQUENCY_DAILY,
                minute: 0,
                hour: 9,
                timezone,
              },
            },
          }),
        });

        expect(findConditionTokens().wrappers.map((token) => token.text())).toEqual(['Schedule']);
        expect(findSchedule().text()).toBe(expected);
        expect(findScheduleBetaBadge().text()).toBe('Beta');
      },
    );
  });

  describe('without a config file', () => {
    it('renders the name of the catalog item', () => {
      createComponent({
        automation: mockFlowTriggerFactory({ configPath: null, configUrl: null }),
      });

      expect(findSource().findComponent(GlIcon).props('name')).toBe('flow-ai');
      expect(findSource().findComponent(GlLink).exists()).toBe(false);
      expect(findSource().text()).toBe('Test Flow');
    });

    it('does not render the source without a catalog item', () => {
      createComponent({
        automation: mockFlowTriggerFactory({
          configPath: null,
          configUrl: null,
          aiCatalogItemConsumer: null,
        }),
      });

      expect(findSource().exists()).toBe(false);
    });
  });

  describe('when the service account is not a project member', () => {
    beforeEach(async () => {
      rolesHandler.mockResolvedValue({
        data: { project: { id: 'gid://gitlab/Project/123', projectMembers: { nodes: [] } } },
      });
      createComponent();
      await waitForPromises();
    });

    it('renders only the service account', () => {
      expect(findServiceAccount().text()).toBe('Flow service account');
    });
  });

  describe('when the role query fails', () => {
    beforeEach(async () => {
      rolesHandler.mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();
    });

    it('reports the error and renders only the service account', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      expect(findServiceAccount().text()).toBe('Flow service account');
    });
  });

  describe('without a service account', () => {
    beforeEach(() => {
      createComponent({ automation: mockFlowTriggerFactory({ user: null }) });
    });

    it('does not fetch the role or render the service account', () => {
      expect(rolesHandler).not.toHaveBeenCalled();
      expect(findServiceAccount().exists()).toBe(false);
    });
  });

  describe('when Escape is pressed', () => {
    beforeEach(() => {
      createComponent();
    });

    afterEach(() => {
      document.body.classList.remove('modal-open');
      resetHTMLFixture();
    });

    it('emits close', () => {
      pressKey();

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('does not emit close for other keys', () => {
      pressKey('Enter');

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('does not emit close after the panel is destroyed', () => {
      wrapper.destroy();
      pressKey();

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('does not emit close while a modal is open', () => {
      document.body.classList.add('modal-open');
      pressKey();

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it.each`
      case                           | html
      ${'an input has focus'}        | ${'<input class="gl-form-input" />'}
      ${'a dropdown item has focus'} | ${'<div class="gl-new-dropdown"><button></button></div>'}
    `('does not emit close when $case', ({ html }) => {
      setHTMLFixture(html);
      document.body.querySelector('input, button').focus();
      pressKey();

      expect(wrapper.emitted('close')).toBeUndefined();
    });
  });
});
