import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupAgentsStep from 'ee/ai/settings/readiness/components/duo_group_agents_step.vue';
import DuoGroupAgentPicker from 'ee/ai/settings/readiness/components/duo_group_agent_picker.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';

const ROOT_GROUP = {
  isSaaS: true,
  showFoundationalAgentsAvailability: true,
  foundationalAgentsOwnerEnabled: true,
};

const SUBGROUP = {
  isSaaS: true,
  foundationalAgentsOwnerEnabled: true,
  duoAgentPlatformOwnerSettingsPath: '/groups/my-group/-/settings/gitlab_duo/configuration',
  rootAncestorName: 'my-group',
};

const SELF_MANAGED_GROUP = {
  isSaaS: false,
  foundationalAgentsOwnerEnabled: true,
  duoAgentPlatformOwnerSettingsPath: '/admin/gitlab_duo',
};

const ALL_ON = {
  foundationalAgentsEnabled: true,
  foundationalAgentsStatuses: [
    { reference: 'a', name: 'Agent A', enabled: true },
    { reference: 'b', name: 'Agent B', enabled: null },
    { reference: 'c', name: 'Agent C', enabled: false },
  ],
  customAgentsEnabled: true,
  externalAgentsEnabled: true,
};

const LOCKED_BY_GROUP = {
  lockedByAncestor: true,
  lockedByApplicationSetting: false,
  ancestorNamespace: { fullName: 'my-group', path: '/my-group' },
};

describe('DuoGroupAgentsStep', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = ROOT_GROUP } = {}) => {
    wrapper = shallowMountExtended(DuoGroupAgentsStep, {
      propsData: { ...ALL_ON, ...props },
      provide,
      stubs: { DuoReadinessRow },
    });
  };

  const findRow = (testId) =>
    wrapper
      .findAllComponents(DuoReadinessRow)
      .wrappers.find((row) => row.attributes('data-testid') === testId);
  const findAgentsToggle = () => wrapper.findComponentByTestId('agents-toggle');
  const findPicker = () => wrapper.findComponent(DuoGroupAgentPicker);
  const findListRow = () => wrapper.findByTestId('foundational-agent-list-row');
  const findToggleDescription = (toggle) => wrapper.find(`#${toggle.props('ariaDescribedby')}`);
  const nestedRows = () => ['foundational-agents-row', 'custom-agents-row', 'external-agents-row'];
  const nestedToggles = () => ['custom-agents-toggle', 'external-agents-toggle'];

  describe('Agents row', () => {
    it('renders a toggle for the owning root group', () => {
      createComponent({ props: { foundationalAgentsEnabled: false } });

      expect(findRow('agents-row').props()).toMatchObject({
        status: 'todo',
        disabled: false,
        description: 'Projects in this group can use agents for tasks and complex questions.',
      });
      expect(findRow('agents-row').find('[data-testid="readiness-row-note"]').text()).toBe(
        'Turn on Agents to change the settings below.',
      );
      expect(findAgentsToggle().props()).toMatchObject({
        value: false,
        disabled: false,
      });

      findAgentsToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-foundational-agents-enabled')).toEqual([[true]]);
    });

    it('drops the note once agents are on', () => {
      createComponent();

      expect(findRow('agents-row').props('status')).toBe('done');
      expect(findRow('agents-row').find('[data-testid="readiness-row-note"]').exists()).toBe(false);
      nestedToggles().forEach((toggle) =>
        expect(wrapper.findComponentByTestId(toggle).props('ariaDescribedby')).toBeUndefined(),
      );
    });

    it('links a subgroup to the owner settings and reads the owner value', () => {
      createComponent({ provide: { ...SUBGROUP, foundationalAgentsOwnerEnabled: false } });

      expect(findAgentsToggle().exists()).toBe(false);
      expect(findRow('agents-row').find('[data-testid="readiness-row-note"]').exists()).toBe(false);
      expect(wrapper.findComponentByTestId('agents-owner-link').props('href')).toBe(
        SUBGROUP.duoAgentPlatformOwnerSettingsPath,
      );
      expect(wrapper.findByTestId('agents-owner-link').text()).toBe('Group settings');
      expect(wrapper.findComponentByTestId('agents-owner-link').props('icon')).toBe(
        'external-link',
      );
      expect(findRow('agents-row').props('status')).toBe('todo');
      expect(findRow('custom-agents-row').props('disabled')).toBe(true);
      expect(wrapper.findComponentByTestId('custom-agents-toggle').props()).toMatchObject({
        accessibleDisabled: true,
        ariaDescribedby: undefined,
      });
    });

    it('disables the nested agent settings while agents are off', () => {
      createComponent({ props: { foundationalAgentsEnabled: false } });

      nestedRows().forEach((row) => expect(findRow(row).props('disabled')).toBe(true));
      expect(findPicker().props('disabled')).toBe(true);
      nestedToggles().forEach((testId) => {
        const toggle = wrapper.findComponentByTestId(testId);

        expect(toggle.props()).toMatchObject({
          value: true,
          disabled: true,
          accessibleDisabled: true,
        });
        expect(findToggleDescription(toggle).text()).toBe(
          'Turn on Agents to change the settings below.',
        );
      });
    });
  });

  describe('Foundational agents row on the top-level group', () => {
    it('renders the picker with the statuses instead of a link to a table', () => {
      createComponent();

      expect(findRow('foundational-agents-row').props()).toMatchObject({
        status: 'done',
        description: 'Projects in this group can use agents built and maintained by GitLab.',
      });
      expect(wrapper.findComponentByTestId('manage-agents-link').exists()).toBe(false);
      expect(findPicker().props()).toMatchObject({
        statuses: ALL_ON.foundationalAgentsStatuses,
        disabled: false,
      });
      expect(findListRow().exists()).toBe(false);
    });

    it('forwards the statuses the picker emits', () => {
      createComponent();

      const statuses = [{ reference: 'a', name: 'Agent A', enabled: false }];
      findPicker().vm.$emit('change', statuses);

      expect(wrapper.emitted('change-foundational-agents-statuses')).toEqual([[statuses]]);
    });

    it('marks the row to do while every agent opted out', () => {
      createComponent({
        props: {
          foundationalAgentsStatuses: [
            { reference: 'a', name: 'Agent A', enabled: false },
            { reference: 'b', name: 'Agent B', enabled: false },
          ],
        },
      });

      expect(findRow('foundational-agents-row').props('status')).toBe('todo');
    });

    it('points the agent checkboxes at the note while agents are off', () => {
      createComponent({ props: { foundationalAgentsEnabled: false } });

      expect(wrapper.find(`#${findPicker().props('describedBy')}`).text()).toBe(
        'Turn on Agents to change the settings below.',
      );
    });

    it('marks the row to do while agents are off', () => {
      createComponent({ props: { foundationalAgentsEnabled: false } });

      expect(findRow('foundational-agents-row').props('status')).toBe('todo');
    });

    it('is absent when the group has no agents', () => {
      createComponent({ props: { foundationalAgentsStatuses: [] } });

      expect(findRow('foundational-agents-row')).toBeUndefined();
      expect(findPicker().exists()).toBe(false);
    });
  });

  describe('Foundational agents row on a subgroup', () => {
    it('lists the agents the top-level group picked, without a picker', () => {
      createComponent({ provide: SUBGROUP });

      expect(findRow('foundational-agents-row').props()).toMatchObject({
        status: 'done',
        description:
          'Projects in this group can use these agents built and maintained by GitLab. Set by my-group.',
      });
      expect(findPicker().exists()).toBe(false);
      expect(
        findListRow()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual(['Agent A', 'Agent B']);
    });

    it('is absent when the top-level group picked no agent', () => {
      createComponent({
        props: {
          foundationalAgentsStatuses: [{ reference: 'a', name: 'Agent A', enabled: false }],
        },
        provide: SUBGROUP,
      });

      expect(findRow('foundational-agents-row')).toBeUndefined();
      expect(findListRow().exists()).toBe(false);
    });

    it('is absent on a self-managed group, where the instance owns the agents', () => {
      createComponent({ provide: SELF_MANAGED_GROUP });

      expect(findRow('foundational-agents-row')).toBeUndefined();
      expect(wrapper.findByTestId('agents-owner-link').text()).toBe('Admin settings');
    });
  });

  it.each`
    setting                                 | row                      | control
    ${'duoCustomAgentsCascadingSettings'}   | ${'custom-agents-row'}   | ${'custom-agents-toggle'}
    ${'duoExternalAgentsCascadingSettings'} | ${'external-agents-row'} | ${'external-agents-toggle'}
  `('locks the $row control when an ancestor locked the setting', ({ setting, row, control }) => {
    createComponent({ provide: { ...ROOT_GROUP, [setting]: LOCKED_BY_GROUP } });

    expect(findRow(row).findComponent(CascadingLockIcon).props()).toMatchObject({
      isLockedByGroupAncestor: true,
      ancestorNamespace: LOCKED_BY_GROUP.ancestorNamespace,
    });
    expect(wrapper.findComponentByTestId(control).props()).toMatchObject({
      disabled: true,
      accessibleDisabled: false,
    });
  });

  it.each`
    toggle                      | event
    ${'custom-agents-toggle'}   | ${'change-custom-agents-enabled'}
    ${'external-agents-toggle'} | ${'change-external-agents-enabled'}
  `('emits $event from the $toggle', ({ toggle, event }) => {
    createComponent();

    wrapper.findComponentByTestId(toggle).vm.$emit('change', false);

    expect(wrapper.emitted(event)).toEqual([[false]]);
  });
});
