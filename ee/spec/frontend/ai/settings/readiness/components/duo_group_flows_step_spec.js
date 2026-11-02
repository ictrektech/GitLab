import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupFlowsStep from 'ee/ai/settings/readiness/components/duo_group_flows_step.vue';
import DuoGroupReadinessRunnerRow from 'ee/ai/settings/readiness/components/duo_group_readiness_runner_row.vue';
import FoundationalFlowPicker from 'ee/ai/settings/components/foundational_flow_picker.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';

const FLOWS = [
  { reference: 'code_review/v1', name: 'Code Review' },
  { reference: 'bug_triage/v1', name: 'Bug Triage' },
  { reference: 'developer/v1', name: 'Developer' },
];

const ALL_ON = {
  remoteFlowsEnabled: true,
  foundationalFlowsEnabled: true,
  customFlowsEnabled: true,
  selectedFoundationalFlowIds: ['code_review/v1'],
};

const LOCKED_BY_GROUP = {
  lockedByAncestor: true,
  lockedByApplicationSetting: false,
  ancestorNamespace: { fullName: 'my-group', path: '/my-group' },
};

const FLOWS_NOTE = 'Turn on Flow execution to change Foundational flows and Custom flows.';

describe('DuoGroupFlowsStep', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(DuoGroupFlowsStep, {
      propsData: { ...ALL_ON, ...props },
      provide: { availableFoundationalFlows: FLOWS, ...provide },
      stubs: { DuoReadinessRow },
    });
  };

  const findRow = (testId) =>
    wrapper
      .findAllComponents(DuoReadinessRow)
      .wrappers.find((row) => row.attributes('data-testid') === testId);
  const findPicker = () => wrapper.findComponent(FoundationalFlowPicker);
  const findPickerRow = () => wrapper.findByTestId('foundational-flow-picker-row');
  const findListRow = () => wrapper.findByTestId('foundational-flow-list-row');
  const findNote = () => findRow('flow-execution-row').find('[data-testid="readiness-row-note"]');
  const findFlowExecutionToggle = () => wrapper.findComponentByTestId('flow-execution-toggle');
  const findCustomFlowsToggle = () => wrapper.findComponentByTestId('custom-flows-toggle');
  const findToggleDescription = (toggle) => wrapper.find(`#${toggle.props('ariaDescribedby')}`);

  it('describes flows and nests the runner row', () => {
    createComponent();

    expect(findRow('flow-execution-row').props('status')).toBe('done');
    expect(findRow('flow-execution-row').text()).toContain(
      'Flows combine one or more agents to solve a complex problem.',
    );
    expect(findNote().exists()).toBe(false);
    expect(findCustomFlowsToggle().props('ariaDescribedby')).toBeUndefined();
    expect(wrapper.findComponent(DuoGroupReadinessRunnerRow).props('nested')).toBe(true);
  });

  it('passes the runner confirmation up', () => {
    createComponent();

    wrapper.findComponent(DuoGroupReadinessRunnerRow).vm.$emit('runner-confirmed', true);

    expect(wrapper.emitted('runner-confirmed')).toEqual([[true]]);
  });

  describe('while flow execution is off', () => {
    beforeEach(() => {
      createComponent({ props: { remoteFlowsEnabled: false } });
    });

    it('mutes the nested rows and disables the flow checkboxes', () => {
      expect(findRow('foundational-flows-row').props()).toMatchObject({
        disabled: true,
        status: 'todo',
        description: 'Projects in this group can use flows built and maintained by GitLab.',
      });
      expect(findPicker().props('disabled')).toBe(true);
      expect(findRow('custom-flows-row').props('description')).toBe(
        'Users with the Maintainer or Owner role for a project can create new flows.',
      );
      expect(findCustomFlowsToggle().props()).toMatchObject({ value: false, disabled: true });
    });

    it('points the muted custom flows toggle at the note', () => {
      expect(findNote().text()).toBe(FLOWS_NOTE);
      expect(findCustomFlowsToggle().props('accessibleDisabled')).toBe(true);
      expect(findToggleDescription(findCustomFlowsToggle()).text()).toBe(FLOWS_NOTE);
    });

    it('points the flow checkboxes at the note', () => {
      expect(wrapper.find(`#${findPicker().props('describedBy')}`).text()).toBe(FLOWS_NOTE);
    });

    it('keeps the flow execution toggle and the runner row enabled', () => {
      expect(findRow('flow-execution-row').props('disabled')).toBe(false);
      expect(findFlowExecutionToggle().props('disabled')).toBe(false);
      expect(wrapper.findComponent(DuoGroupReadinessRunnerRow).exists()).toBe(true);
    });
  });

  it('shows no note when an ancestor locked flow execution off', () => {
    createComponent({
      props: { remoteFlowsEnabled: false },
      provide: { duoRemoteFlowsCascadingSettings: LOCKED_BY_GROUP },
    });

    expect(findNote().exists()).toBe(false);
    expect(findCustomFlowsToggle().props()).toMatchObject({
      disabled: true,
      accessibleDisabled: true,
      ariaDescribedby: undefined,
    });
  });

  describe('foundational flows on the top-level group', () => {
    it('renders the picker with Select all instead of a toggle', () => {
      createComponent();

      expect(wrapper.findComponentByTestId('foundational-flows-toggle').exists()).toBe(false);
      expect(findPicker().props()).toMatchObject({
        value: ['code_review/v1'],
        disabled: false,
        selectAll: true,
      });
      expect(findRow('foundational-flows-row').props('status')).toBe('done');
    });

    it('marks the row todo while no flow is selected', () => {
      createComponent({ props: { selectedFoundationalFlowIds: [] } });

      expect(findRow('foundational-flows-row').props('status')).toBe('todo');
    });

    it('marks the row todo while foundational flows are off despite a selection', () => {
      createComponent({ props: { foundationalFlowsEnabled: false } });

      expect(findRow('foundational-flows-row').props('status')).toBe('todo');
    });

    it('hides the picker when no flow is available', () => {
      createComponent({ provide: { availableFoundationalFlows: [] } });

      expect(findPickerRow().exists()).toBe(false);
      expect(findListRow().exists()).toBe(false);
    });

    it('forwards the selection and the consent from the picker', () => {
      createComponent();

      findPicker().vm.$emit('input', ['code_review/v1', 'bug_triage/v1']);
      findPicker().vm.$emit('consent-given');

      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([
        [['code_review/v1', 'bug_triage/v1']],
      ]);
      expect(wrapper.emitted('change-foundational-flows-enabled')).toBeUndefined();
      expect(wrapper.emitted('consent-given')).toHaveLength(1);
    });

    it('turns foundational flows off when the last flow is deselected', () => {
      createComponent();

      findPicker().vm.$emit('input', []);

      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([[[]]]);
      expect(wrapper.emitted('change-foundational-flows-enabled')).toEqual([[false]]);
    });

    it('turns foundational flows back on with the first selected flow', () => {
      createComponent({
        props: { foundationalFlowsEnabled: false, selectedFoundationalFlowIds: [] },
      });

      findPicker().vm.$emit('input', ['developer/v1']);

      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([[['developer/v1']]]);
      expect(wrapper.emitted('change-foundational-flows-enabled')).toEqual([[true]]);
    });
  });

  describe('turning flow execution on', () => {
    const firstSetup = { remoteFlowsEnabled: false, selectedFoundationalFlowIds: [] };

    it('selects every flow except Code Review while its consent is still needed', () => {
      createComponent({
        props: firstSetup,
        provide: { duoEnterpriseActive: true, initialCodeReviewFlowConsentGiven: false },
      });

      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-remote-flows-enabled')).toEqual([[true]]);
      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([
        [['bug_triage/v1', 'developer/v1']],
      ]);
    });

    it('selects Code Review too once its consent was given', () => {
      createComponent({
        props: firstSetup,
        provide: { duoEnterpriseActive: true, initialCodeReviewFlowConsentGiven: true },
      });

      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([
        [['code_review/v1', 'bug_triage/v1', 'developer/v1']],
      ]);
    });

    it('selects Code Review too once its consent was given in this session', () => {
      createComponent({
        props: firstSetup,
        provide: { duoEnterpriseActive: true, initialCodeReviewFlowConsentGiven: false },
      });

      findPicker().vm.$emit('consent-given');
      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('consent-given')).toHaveLength(1);
      expect(wrapper.emitted('change-selected-flow-ids')).toEqual([
        [['code_review/v1', 'bug_triage/v1', 'developer/v1']],
      ]);
    });

    it('also turns foundational flows on when they were off', () => {
      createComponent({ props: { ...firstSetup, foundationalFlowsEnabled: false } });

      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-foundational-flows-enabled')).toEqual([[true]]);
    });

    it('turns foundational flows back on when flows were already selected', () => {
      createComponent({ props: { remoteFlowsEnabled: false, foundationalFlowsEnabled: false } });

      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-foundational-flows-enabled')).toEqual([[true]]);
      expect(wrapper.emitted('change-selected-flow-ids')).toBeUndefined();
    });

    it.each`
      state                                      | props                            | provide
      ${'flows are already selected'}            | ${{ remoteFlowsEnabled: false }} | ${{}}
      ${'an ancestor locked foundational flows'} | ${firstSetup}                    | ${{ duoFoundationalFlowsCascadingSettings: LOCKED_BY_GROUP }}
      ${'the group is a subgroup'}               | ${firstSetup}                    | ${{ groupIsRoot: false }}
      ${'no flow is available'}                  | ${firstSetup}                    | ${{ availableFoundationalFlows: [] }}
    `('leaves the selection alone when $state', ({ props, provide }) => {
      createComponent({ props, provide });

      findFlowExecutionToggle().vm.$emit('change', true);

      expect(wrapper.emitted('change-remote-flows-enabled')).toEqual([[true]]);
      expect(wrapper.emitted('change-selected-flow-ids')).toBeUndefined();
    });

    it('leaves the selection alone when flow execution turns off', () => {
      createComponent();

      findFlowExecutionToggle().vm.$emit('change', false);

      expect(wrapper.emitted('change-remote-flows-enabled')).toEqual([[false]]);
      expect(wrapper.emitted('change-selected-flow-ids')).toBeUndefined();
    });
  });

  describe('on a subgroup', () => {
    const subgroup = { groupIsRoot: false, rootAncestorName: 'my-group' };

    it('lists the flows the top-level group picked instead of the picker', () => {
      createComponent({
        props: { selectedFoundationalFlowIds: [] },
        provide: { ...subgroup, availableFoundationalFlows: [FLOWS[0], FLOWS[2]] },
      });

      expect(findPickerRow().exists()).toBe(false);
      expect(findRow('foundational-flows-row').props()).toMatchObject({
        status: 'done',
        description:
          'Projects in this group can use these flows built and maintained by GitLab. Set by my-group.',
      });
      expect(
        findListRow()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual(['Code Review', 'Developer']);
    });

    it('shows no list when the top-level group picked nothing', () => {
      createComponent({
        props: { selectedFoundationalFlowIds: [] },
        provide: { ...subgroup, availableFoundationalFlows: [] },
      });

      expect(findListRow().exists()).toBe(false);
      expect(findRow('foundational-flows-row').props('status')).toBe('todo');
    });
  });

  it.each`
    setting                              | row                     | control
    ${'duoRemoteFlowsCascadingSettings'} | ${'flow-execution-row'} | ${'flow-execution-toggle'}
    ${'duoCustomFlowsCascadingSettings'} | ${'custom-flows-row'}   | ${'custom-flows-toggle'}
  `('locks the $row control when an ancestor locked the setting', ({ setting, row, control }) => {
    createComponent({ provide: { [setting]: LOCKED_BY_GROUP } });

    expect(findRow(row).findComponent(CascadingLockIcon).props()).toMatchObject({
      isLockedByGroupAncestor: true,
      ancestorNamespace: LOCKED_BY_GROUP.ancestorNamespace,
    });
    expect(wrapper.findComponentByTestId(control).props()).toMatchObject({
      disabled: true,
      accessibleDisabled: false,
    });
  });

  it('locks the flow checkboxes when an ancestor locked foundational flows', () => {
    createComponent({ provide: { duoFoundationalFlowsCascadingSettings: LOCKED_BY_GROUP } });

    expect(
      findRow('foundational-flows-row').findComponent(CascadingLockIcon).props(),
    ).toMatchObject({
      isLockedByGroupAncestor: true,
      ancestorNamespace: LOCKED_BY_GROUP.ancestorNamespace,
    });
    expect(findPicker().props('disabled')).toBe(true);
  });

  it.each`
    toggle                     | event
    ${'flow-execution-toggle'} | ${'change-remote-flows-enabled'}
    ${'custom-flows-toggle'}   | ${'change-custom-flows-enabled'}
  `('emits $event from the $toggle', ({ toggle, event }) => {
    createComponent();

    wrapper.findComponentByTestId(toggle).vm.$emit('change', false);

    expect(wrapper.emitted(event)).toEqual([[false]]);
  });
});
