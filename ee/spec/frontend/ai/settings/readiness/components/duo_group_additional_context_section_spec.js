import { GlToggle } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupAdditionalContextSection from 'ee/ai/settings/readiness/components/duo_group_additional_context_section.vue';
import DuoGroupReadinessMcpRow from 'ee/ai/settings/readiness/components/duo_group_readiness_mcp_row.vue';
import DuoReadinessOrbitRow from 'ee/ai/settings/readiness/components/duo_readiness_orbit_row.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoReadinessSection from '~/ai/settings/readiness/components/duo_readiness_section.vue';

const ROOT_GROUP = {
  onGeneralSettingsPage: false,
  duoWorkflowMcpRootEnabled: false,
  duoAgentPlatformOwnerSettingsPath: null,
  mcpServersAvailable: true,
};

const SUBGROUP = {
  onGeneralSettingsPage: true,
  duoWorkflowMcpRootEnabled: true,
  duoAgentPlatformOwnerSettingsPath: '/groups/my-group/-/settings/gitlab_duo/configuration',
  mcpServersAvailable: true,
};

describe('DuoGroupAdditionalContextSection', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = ROOT_GROUP } = {}) => {
    wrapper = shallowMountExtended(DuoGroupAdditionalContextSection, {
      propsData: { mcpAvailable: true, mcpEnabled: false, ...props },
      provide,
    });
  };

  const findSection = () => wrapper.findComponent(DuoReadinessSection);
  const findOrbitRow = () => wrapper.findComponent(DuoReadinessOrbitRow);
  const findIdeAccessRow = () => wrapper.findComponentByTestId('ide-access-row');
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findViewButton = () => wrapper.findComponentByTestId('ide-access-view-button');

  it('hides the MCP tools row when MCP servers are not available to the viewer', () => {
    createComponent({ provide: { ...ROOT_GROUP, mcpServersAvailable: false } });

    expect(wrapper.findComponent(DuoGroupReadinessMcpRow).exists()).toBe(false);
    expect(findIdeAccessRow().exists()).toBe(true);
  });

  it('renders the section with the MCP tools row first', () => {
    createComponent();

    expect(findSection().props()).toMatchObject({
      title: 'Additional context',
      subtitle: 'Features that give agents more context to work with.',
      headingTag: 'h2',
    });
    expect(wrapper.findComponent(DuoGroupReadinessMcpRow).exists()).toBe(true);
    expect(wrapper.findAllComponents(DuoReadinessRow).at(0).props('title')).toBe('IDE access');
  });

  describe('GitLab Orbit row', () => {
    const duoOrbit = {
      enabled: false,
      canEnable: true,
      rootGroupPath: 'my-group',
      graphPath: '/-/dashboard/orbit',
    };

    it('renders first, as a group row, when Orbit is available', () => {
      createComponent({ provide: { ...ROOT_GROUP, groupFullPath: 'my-group', duoOrbit } });

      expect(findOrbitRow().props()).toMatchObject({
        group: true,
        orbit: duoOrbit,
        fullPath: 'my-group',
      });
      expect(findSection().element.firstElementChild).toBe(findOrbitRow().element);
    });

    it('is hidden when Orbit is not available', () => {
      createComponent();

      expect(findOrbitRow().exists()).toBe(false);
    });
  });

  it('uses a lower heading level inside the General settings page', () => {
    createComponent({ provide: { ...ROOT_GROUP, onGeneralSettingsPage: true } });

    expect(findSection().props('headingTag')).toBe('h4');
  });

  describe('IDE access on a top-level group that controls it', () => {
    it('is to-do with the toggle off', () => {
      createComponent();

      expect(findIdeAccessRow().props()).toMatchObject({
        status: 'todo',
        description: 'Allow the IDE to access external MCP tools.',
      });
      expect(findToggle().props('value')).toBe(false);
      expect(findViewButton().exists()).toBe(false);
    });

    it('is done with the toggle on', () => {
      createComponent({ props: { mcpEnabled: true } });

      expect(findIdeAccessRow().props('status')).toBe('done');
      expect(findToggle().props('value')).toBe(true);
    });

    it('reports toggle changes to the form', () => {
      createComponent();

      findToggle().vm.$emit('change', true);

      expect(wrapper.emitted('mcp-change')).toEqual([[true]]);
    });
  });

  describe('IDE access on a subgroup', () => {
    it("reads the top-level group's value and links to its settings", () => {
      createComponent({ props: { mcpAvailable: false }, provide: SUBGROUP });

      expect(findIdeAccessRow().props('status')).toBe('done');
      expect(findToggle().exists()).toBe(false);
      expect(findViewButton().text()).toBe('View');
      expect(findViewButton().attributes('href')).toBe(
        '/groups/my-group/-/settings/gitlab_duo/configuration',
      );
    });

    it('offers no control when the owner cannot reach the top-level group settings', () => {
      createComponent({
        props: { mcpAvailable: false },
        provide: { ...SUBGROUP, duoAgentPlatformOwnerSettingsPath: null },
      });

      expect(findToggle().exists()).toBe(false);
      expect(findViewButton().exists()).toBe(false);
    });
  });
});
