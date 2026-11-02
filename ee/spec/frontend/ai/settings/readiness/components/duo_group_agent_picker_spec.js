import { GlFormCheckbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupAgentPicker from 'ee/ai/settings/readiness/components/duo_group_agent_picker.vue';

const STATUSES = [
  { reference: 'planner', name: 'Planner', description: 'Plans work.', enabled: true },
  { reference: 'security', name: 'Security Analyst', description: 'Finds risks.', enabled: null },
  { reference: 'data', name: 'Data Analyst', description: 'Reads data.', enabled: false },
];

describe('DuoGroupAgentPicker', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(DuoGroupAgentPicker, {
      propsData: { statuses: STATUSES, ...props },
    });
  };

  const findSelectAll = () => wrapper.findComponentByTestId('foundational-agent-select-all');
  const findAgentCheckboxes = () =>
    wrapper
      .findAllComponents(GlFormCheckbox)
      .wrappers.filter((box) => box.attributes('data-testid') === 'foundational-agent-checkbox');

  it('points the checkboxes at the note they are described by', () => {
    createComponent({ props: { describedBy: 'agents-note' } });

    expect(findSelectAll().attributes('aria-describedby')).toBe('agents-note');
    expect(findAgentCheckboxes().map((box) => box.attributes('aria-describedby'))).toEqual([
      'agents-note',
      'agents-note',
      'agents-note',
    ]);
  });

  it('renders one checkbox per agent, checked unless the agent opted out', () => {
    createComponent();

    expect(findAgentCheckboxes().map((box) => box.props('checked'))).toEqual([true, true, false]);
    expect(findAgentCheckboxes()[1].text()).toContain('Security Analyst');
    expect(findAgentCheckboxes()[1].text()).toContain('Finds risks.');
  });

  it.each`
    statuses                                                   | checked  | indeterminate
    ${STATUSES}                                                | ${false} | ${true}
    ${STATUSES.map((agent) => ({ ...agent, enabled: true }))}  | ${true}  | ${false}
    ${STATUSES.map((agent) => ({ ...agent, enabled: false }))} | ${false} | ${false}
  `(
    'renders Select all as checked=$checked indeterminate=$indeterminate',
    ({ statuses, checked, indeterminate }) => {
      createComponent({ props: { statuses } });

      expect(findSelectAll().props()).toMatchObject({ checked, indeterminate });
    },
  );

  it('disables every checkbox', () => {
    createComponent({ props: { disabled: true } });

    expect(findSelectAll().props('disabled')).toBe(true);
    findAgentCheckboxes().forEach((box) => expect(box.props('disabled')).toBe(true));
  });

  it('emits the statuses with the toggled agent set explicitly', () => {
    createComponent();

    findAgentCheckboxes()[1].vm.$emit('change', false);
    findAgentCheckboxes()[2].vm.$emit('change', true);

    expect(wrapper.emitted('change')).toEqual([
      [[STATUSES[0], { ...STATUSES[1], enabled: false }, STATUSES[2]]],
      [[STATUSES[0], STATUSES[1], { ...STATUSES[2], enabled: true }]],
    ]);
  });

  it('emits every agent set explicitly from Select all', () => {
    createComponent();

    findSelectAll().vm.$emit('change', true);
    findSelectAll().vm.$emit('change', false);

    expect(wrapper.emitted('change')).toEqual([
      [STATUSES.map((agent) => ({ ...agent, enabled: true }))],
      [STATUSES.map((agent) => ({ ...agent, enabled: false }))],
    ]);
  });
});
