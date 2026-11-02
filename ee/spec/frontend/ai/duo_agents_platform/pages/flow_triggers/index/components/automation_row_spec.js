import { GlBadge, GlDisclosureDropdown, GlIcon, GlToggle, GlTruncate } from '@gitlab/ui';
import { useFakeDate } from 'helpers/fake_date';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AutomationRow from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_row.vue';
import {
  FLOW_TRIGGER_MODE_SCHEDULE,
  SCHEDULE_FREQUENCY_DAILY,
} from 'ee/ai/duo_agents_platform/constants';
import {
  FLOW_TRIGGERS_EDIT_ROUTE,
  FLOW_TRIGGERS_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { mockFlowTriggerFactory, mockLastRunFactory, mockTrigger } from '../../mocks';

describe('AutomationRow', () => {
  let wrapper;

  const findDescription = () => wrapper.findComponentByTestId('automation-description');
  const findConditions = () => wrapper.findByTestId('automation-conditions');
  const findToggle = () => wrapper.findComponent(GlToggle);
  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findRunningSessions = () => wrapper.findByTestId('automation-running-sessions');
  const findLastRunError = () => wrapper.findComponentByTestId('automation-last-run-error');

  const timezoneData = [
    { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
  ];

  const createComponent = ({
    automation = mockTrigger,
    isToggling = false,
    isSelected = false,
    glAbilities = { manageAiFlowTriggers: true },
  } = {}) => {
    wrapper = shallowMountExtended(AutomationRow, {
      propsData: { automation, isToggling, isSelected },
      provide: { timezoneData, glAbilities },
      mocks: { $route: { query: { foo: 'bar' } } },
    });
  };

  it('renders the description as a link to the automation that keeps the query', () => {
    createComponent();

    expect(findDescription().text()).toBe('Test trigger');
    expect(findDescription().attributes('data-automation-id')).toBe(mockTrigger.id);
    expect(findDescription().props('to')).toEqual({
      name: FLOW_TRIGGERS_SHOW_ROUTE,
      params: { id: 1 },
      query: { foo: 'bar' },
    });
  });

  it.each([true, false])('applies the selected background when isSelected is %s', (isSelected) => {
    createComponent({ isSelected });

    expect(wrapper.classes('gl-bg-strong')).toBe(isSelected);
  });

  it.each`
    case                                           | filter                                                                                                                         | icon                | text                                                   | beta
    ${'event conditions'}                          | ${{}}                                                                                                                          | ${'trigger-source'} | ${'Mention, Assign'}                                   | ${false}
    ${'schedule summary with a known timezone'}    | ${{ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_DAILY, minute: 0, hour: 9, timezone: 'America/New_York' } }} | ${'clock'}          | ${'Daily at 09:00 [UTC-5] Eastern Time (US & Canada)'} | ${true}
    ${'schedule summary with an unknown timezone'} | ${{ [FLOW_TRIGGER_MODE_SCHEDULE]: { frequency: SCHEDULE_FREQUENCY_DAILY, minute: 0, hour: 9, timezone: 'Etc/UTC' } }}          | ${'clock'}          | ${'Daily at 09:00 Etc/UTC'}                            | ${true}
  `('renders the $case', ({ filter, icon, text, beta }) => {
    createComponent({ automation: mockFlowTriggerFactory({ filter }) });

    expect(findConditions().findComponent(GlIcon).props('name')).toBe(icon);
    expect(findConditions().findComponent(GlTruncate).props('text')).toBe(text);
    expect(wrapper.findByTestId('automation-schedule-beta-badge').exists()).toBe(beta);
  });

  describe('last run', () => {
    useFakeDate(2026, 9, 13, 11);

    it('renders a "Never run" badge without a tooltip when the automation has no runs', () => {
      createComponent();

      expect(findBadge().props()).toMatchObject({ variant: 'neutral', icon: 'status-neutral' });
      expect(findBadge().text()).toBe('Never run');
      expect(findBadge().attributes('title')).toBeUndefined();
      expect(findBadge().attributes('tabindex')).toBeUndefined();
    });

    it.each`
      case            | lastRun                                                               | variant      | text                | title
      ${'finished'}   | ${mockLastRunFactory()}                                               | ${'success'} | ${'Succeeded'}      | ${'Finished 58 minutes ago'}
      ${'unfinished'} | ${mockLastRunFactory({ status: 'AWAITING_INPUT', finishedAt: null })} | ${'warning'} | ${'Awaiting input'} | ${'Started 1 hour ago'}
    `(
      'renders a focusable status badge with the time for a $case run',
      ({ lastRun, variant, text, title }) => {
        createComponent({ automation: mockFlowTriggerFactory({ lastRun }) });

        expect(findBadge().props('variant')).toBe(variant);
        expect(findBadge().text()).toBe(text);
        expect(findBadge().attributes()).toMatchObject({ title, tabindex: '0' });
      },
    );

    it.each`
      runningCount | text
      ${1}         | ${'1 session'}
      ${2}         | ${'2 sessions'}
    `('renders "$text" instead of the error', ({ runningCount, text }) => {
      createComponent({
        automation: mockFlowTriggerFactory({
          runningCount,
          lastRun: mockLastRunFactory({ error: 'Boom' }),
        }),
      });

      expect(findRunningSessions().text()).toBe(text);
      expect(findLastRunError().exists()).toBe(false);
    });

    it('renders the error of the last run when no session is running', () => {
      createComponent({
        automation: mockFlowTriggerFactory({
          runningCount: 0,
          lastRun: mockLastRunFactory({ status: 'FAILED', error: 'Flow not found' }),
        }),
      });

      expect(findLastRunError().props()).toMatchObject({
        text: 'Flow not found',
        withTooltip: true,
      });
      expect(findLastRunError().attributes('tabindex')).toBe('0');
    });
  });

  it('renders the toggle with a stable label and emits toggle on change', () => {
    createComponent({ isToggling: true });

    expect(findToggle().props()).toMatchObject({
      value: true,
      isLoading: true,
      disabled: false,
      label: 'Turn automation on or off: Test trigger',
    });

    findToggle().vm.$emit('change', false);

    expect(wrapper.emitted('toggle')).toEqual([[{ id: mockTrigger.id, active: false }]]);
  });

  it('renders the edit and delete actions', () => {
    createComponent();

    const [edit, remove] = findDropdown().props('items');

    expect(edit.text).toBe('Edit automation');
    expect(remove.text).toBe('Delete automation');

    edit.action();
    remove.action();

    expect(wrapper.emitted('edit')).toEqual([[mockTrigger]]);
    expect(wrapper.emitted('delete')).toEqual([[mockTrigger.id]]);
  });

  it('links to the edit page when event types have different goals', () => {
    createComponent({
      automation: mockFlowTriggerFactory({ goals: { mention: 'Review', assign: 'Fix' } }),
    });

    const [edit] = findDropdown().props('items');

    expect(edit).toMatchObject({
      to: { name: FLOW_TRIGGERS_EDIT_ROUTE, params: { id: 1 } },
    });
    expect(edit.action).toBeUndefined();
  });

  it('disables the toggle and hides the actions without the ability to manage', () => {
    createComponent({ glAbilities: { manageAiFlowTriggers: false } });

    expect(findToggle().props('disabled')).toBe(true);
    expect(findDropdown().exists()).toBe(false);
  });
});
