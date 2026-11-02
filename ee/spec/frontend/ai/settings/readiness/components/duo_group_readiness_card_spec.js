import { GlAlert, GlProgressBar } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupReadinessCard from 'ee/ai/settings/readiness/components/duo_group_readiness_card.vue';
import { AVAILABILITY_OPTIONS } from 'ee/ai/settings/constants';
import DuoReadinessSection from '~/ai/settings/readiness/components/duo_readiness_section.vue';

const ROOT_GROUP = {
  isSaaS: true,
  onGeneralSettingsPage: false,
  showDuoAgentPlatformEnablementSetting: true,
  showFoundationalAgentsAvailability: true,
  duoAgentPlatformOwnerEnabled: true,
  foundationalAgentsOwnerEnabled: true,
  rootAncestorName: 'my-group',
};

const SUBGROUP = {
  isSaaS: true,
  onGeneralSettingsPage: true,
  duoAgentPlatformOwnerEnabled: true,
  foundationalAgentsOwnerEnabled: true,
  rootAncestorName: 'my-group',
};

const SELF_MANAGED = { ...SUBGROUP, isSaaS: false };

const ALL_ON = {
  duoAvailability: AVAILABILITY_OPTIONS.DEFAULT_ON,
  duoAgentPlatformEnabled: true,
  foundationalAgentsEnabled: true,
  remoteFlowsEnabled: true,
  runnerConfirmed: true,
};

const LOCKED_BY_GROUP = {
  lockedByAncestor: true,
  lockedByApplicationSetting: false,
  ancestorNamespace: { fullName: 'my-group', path: '/my-group' },
};

describe('DuoGroupReadinessCard', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = ROOT_GROUP } = {}) => {
    wrapper = shallowMountExtended(DuoGroupReadinessCard, {
      propsData: { ...ALL_ON, ...props },
      provide,
      stubs: { DuoReadinessSection },
      slots: { default: '<p data-testid="slot-content">rows</p>' },
    });
  };

  const findHeading = () => wrapper.findByTestId('readiness-heading');
  const findStateLine = () => wrapper.findByTestId('readiness-state-line');
  const findProgressLabel = () => wrapper.findByTestId('readiness-progress-count');
  const findProgressBar = () => wrapper.findComponent(GlProgressBar);
  const findProgressWarning = () => wrapper.findByTestId('readiness-progress-warning');
  const findNotice = () => wrapper.findComponent(GlAlert);
  const findSlotContent = () => wrapper.findByTestId('slot-content');

  describe('header', () => {
    it('summarizes the four steps', () => {
      createComponent({ props: { remoteFlowsEnabled: false } });

      expect(findHeading().text()).toBe('Run GitLab Duo agents and flows in this group');
      expect(findStateLine().text()).toBe('Agents work now. 1 more step to set up flows.');
      expect(findProgressLabel().text()).toBe('1 step left');
      expect(findProgressWarning().exists()).toBe(false);
      expect(findProgressBar().props()).toMatchObject({
        value: 3,
        max: 4,
        variant: 'primary',
        ariaLabel: 'Agent setup progress: 3 of 4 steps complete',
      });
    });

    it('warns when the four steps are on but no runner is confirmed', () => {
      createComponent({ props: { runnerConfirmed: false } });

      expect(findProgressLabel().text()).toBe('Runner needed');
      expect(findProgressLabel().classes()).toContain('gl-text-warning');
      expect(findProgressWarning().exists()).toBe(true);
      expect(findProgressBar().props()).toMatchObject({ value: 4, variant: 'warning' });
      expect(findStateLine().text()).toBe(
        "Agents work now. Flows are on, but they won't start until you connect a runner.",
      );
    });

    it('reads the owner value for the steps a subgroup does not own', () => {
      createComponent({
        props: { duoAgentPlatformEnabled: false, foundationalAgentsEnabled: false },
        provide: SUBGROUP,
      });

      expect(findStateLine().text()).toBe('Agents and flows are ready in this group.');
      expect(findProgressLabel().text()).toBe('Setup complete');
      expect(findProgressBar().props()).toMatchObject({ value: 4, variant: 'success' });
    });

    it('reads blocked when the owner has the Agent Platform off', () => {
      createComponent({ provide: { ...SUBGROUP, duoAgentPlatformOwnerEnabled: false } });

      expect(findProgressLabel().text()).toBe('Blocked');
      expect(findStateLine().text()).toBe('Agent Platform is off for my-group.');
    });

    it('leaves a step the root group locked off out of the count and names the group', () => {
      createComponent({
        props: { remoteFlowsEnabled: false },
        provide: { ...SUBGROUP, duoRemoteFlowsCascadingSettings: LOCKED_BY_GROUP },
      });

      expect(findStateLine().text()).toBe('Agents work now. Flows are turned off by my-group.');
      expect(findProgressLabel().text()).toBe('Limited by my-group');
      expect(findProgressBar().props('value')).toBe(3);
    });

    it('names the administrator when the instance locked GitLab Duo off', () => {
      createComponent({
        props: { duoAvailability: AVAILABILITY_OPTIONS.NEVER_ON },
        provide: { ...SELF_MANAGED, duoAvailabilityAdminLocked: true },
      });

      expect(findStateLine().text()).toBe(
        'GitLab Duo is turned off by an administrator. Settings you change here take effect when GitLab Duo is turned on.',
      );
      expect(findProgressLabel().text()).toBe('Limited by your administrator');
    });

    it('names each party when a parent group and an administrator locked different steps', () => {
      createComponent({
        props: { remoteFlowsEnabled: false },
        provide: {
          ...SUBGROUP,
          duoAvailabilityCascadingSettings: LOCKED_BY_GROUP,
          duoRemoteFlowsCascadingSettings: {
            lockedByAncestor: false,
            lockedByApplicationSetting: true,
          },
        },
      });

      expect(findStateLine().text()).toBe(
        'Agents work now. Flows are turned off by an administrator.',
      );
      expect(findProgressLabel().text()).toBe('Limited by your administrator');
    });

    it('renders the heading as the page title on the configuration page', () => {
      createComponent();

      expect(findHeading().element.tagName).toBe('H1');
      expect(wrapper.findByTestId('readiness-section-title').element.tagName).toBe('H2');
    });

    it('nests the headings inside the general settings block', () => {
      createComponent({ provide: SUBGROUP });

      expect(findHeading().element.tagName).toBe('H3');
      expect(wrapper.findByTestId('readiness-section-title').element.tagName).toBe('H4');
    });
  });

  describe('namespace notice', () => {
    it('is absent for a root group', () => {
      createComponent();

      expect(findNotice().exists()).toBe(false);
    });

    it('is absent for a subgroup without ancestor locks', () => {
      createComponent({ provide: SUBGROUP });

      expect(findNotice().exists()).toBe(false);
    });

    it('names the root group when an ancestor locked a setting', () => {
      createComponent({
        provide: { ...SUBGROUP, duoRemoteFlowsCascadingSettings: LOCKED_BY_GROUP },
      });

      expect(findNotice().props('title')).toBe('Inherited from my-group');
      expect(findNotice().text()).toBe(
        'Some settings are set by my-group. To change them, ask an Owner of my-group.',
      );
    });

    it('points self-managed groups to the instance', () => {
      createComponent({ provide: SELF_MANAGED });

      expect(findNotice().props('title')).toBe(
        'Agent Platform is controlled at the instance level',
      );
      expect(findNotice().text()).toBe(
        "An instance administrator turns on Agent Platform, Orbit, and MCP tools for every group on the instance. It can't be set here.",
      );
    });
  });

  describe('step rows slot', () => {
    it('renders the rows inside the section', () => {
      createComponent();

      expect(wrapper.findComponent(DuoReadinessSection).props()).toMatchObject({
        title: 'Agent and flow setup',
        subtitle:
          "Projects in this group follow these settings. If you turn one off, projects can't turn it on.",
      });
      expect(findSlotContent().text()).toBe('rows');
    });
  });
});
