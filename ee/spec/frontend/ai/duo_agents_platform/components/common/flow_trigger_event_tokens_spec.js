import { shallowMount } from '@vue/test-utils';
import { GlBadge, GlToken } from '@gitlab/ui';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import FlowTriggerEventTokens from 'ee/ai/duo_agents_platform/components/common/flow_trigger_event_tokens.vue';
import { buildPipelineHooksFilter } from 'ee_jest/ai/duo_agents_platform/mock_data';

describe('FlowTriggerEventTokens', () => {
  let wrapper;

  const timezoneData = [
    { identifier: 'America/New_York', name: 'Eastern Time (US & Canada)', offset: -18000 },
  ];

  const createComponent = (flowTrigger) => {
    wrapper = shallowMount(FlowTriggerEventTokens, {
      propsData: { flowTrigger },
      provide: { timezoneData },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findTokens = () => wrapper.findAllComponents(GlToken);
  const findToken = () => findTokens().at(0);
  const findTooltip = () => getBinding(findToken().element, 'gl-tooltip').value;
  const tokenTexts = () => findTokens().wrappers.map((token) => token.text());

  it('renders one token per event type using the base label', () => {
    createComponent({ eventTypes: [0, 1], filter: {} });

    expect(tokenTexts()).toEqual(['Mention', 'Assign']);
  });

  it('appends pipeline statuses to the pipeline events token', () => {
    createComponent({
      eventTypes: [3],
      filter: buildPipelineHooksFilter({ value: ['failed', 'canceled'] }),
    });

    expect(tokenTexts()).toEqual(['Pipeline events (Failed, Canceled)']);
  });

  it('appends the configured action to the work item token', () => {
    createComponent({
      eventTypes: [7],
      filter: { work_item: { rules: [{ field: 'action', operator: 'in', value: ['created'] }] } },
    });

    expect(tokenTexts()).toEqual(['Work item (Created)']);
  });

  it('names commit_to_default_branch (8) rather than mislabelling it', () => {
    createComponent({ eventTypes: [8], filter: {} });

    expect(tokenTexts()).toEqual(['Commit to default branch']);
  });

  describe('scheduled (9)', () => {
    describe('with a schedule that has a timezone', () => {
      beforeEach(() => {
        createComponent({
          eventTypes: [9],
          filter: {
            scheduled: {
              frequency: 'WEEKLY',
              minute: 30,
              hour: 9,
              dayOfWeek: 1,
              timezone: 'America/New_York',
            },
          },
        });
      });

      it('describes the day and time without the timezone', () => {
        expect(tokenTexts()).toEqual(['Schedule (Weekly on Monday at 09:30)']);
      });

      it('marks the schedule as beta', () => {
        expect(wrapper.findComponent(GlBadge).text()).toBe('Beta');
      });

      it('shows the timezone, formatted like the timezone picker, in a focusable tooltip', () => {
        expect(findTooltip()).toBe('[UTC-5] Eastern Time (US & Canada)');
        expect(findToken().attributes('tabindex')).toBe('0');
      });
    });

    describe('with a timezone missing from the timezone data', () => {
      beforeEach(() => {
        createComponent({
          eventTypes: [9],
          filter: { scheduled: { frequency: 'HOURLY', minute: 15, timezone: 'Etc/UTC' } },
        });
      });

      it('falls back to the IANA identifier in the tooltip', () => {
        expect(findTooltip()).toBe('Etc/UTC');
      });
    });

    describe('with a frequency that has no timezone field', () => {
      beforeEach(() => {
        // A stray timezone (e.g. saved through the API) must not surface for this frequency.
        createComponent({
          eventTypes: [9],
          filter: { scheduled: { frequency: 'EVERY_15_MINUTES', timezone: 'Etc/UTC' } },
        });
      });

      it('names the frequency', () => {
        expect(tokenTexts()).toEqual(['Schedule (Every 15 minutes)']);
      });

      it('has no tooltip and is not focusable', () => {
        expect(findTooltip()).toBe('');
        expect(findToken().attributes('tabindex')).toBeUndefined();
      });
    });

    describe('with an incomplete schedule', () => {
      beforeEach(() => {
        createComponent({ eventTypes: [9], filter: { scheduled: { frequency: 'WEEKLY' } } });
      });

      it('renders a bare "Schedule" token with no tooltip', () => {
        expect(tokenTexts()).toEqual(['Schedule']);
        expect(findTooltip()).toBe('');
      });
    });
  });

  describe('with a non-schedule event type', () => {
    beforeEach(() => {
      createComponent({ eventTypes: [0], filter: {} });
    });

    it('has no tooltip and is not focusable', () => {
      expect(findTooltip()).toBe('');
      expect(findToken().attributes('tabindex')).toBeUndefined();
    });

    it('does not mark the event as beta', () => {
      expect(wrapper.findComponent(GlBadge).exists()).toBe(false);
    });
  });

  describe('merge request folding', () => {
    it('folds merge_request_ready (4) into a "Merge request (Marked ready)" token', () => {
      createComponent({ eventTypes: [4], filter: {} });

      expect(tokenTexts()).toEqual(['Merge request (Marked ready)']);
    });

    it('folds merge_request_code_conflict (5) into a "Merge request (Merge conflict)" token', () => {
      createComponent({ eventTypes: [5], filter: {} });

      expect(tokenTexts()).toEqual(['Merge request (Merge conflict)']);
    });

    it('renders a bare "Merge request" token for merge_request (6) with no action filter', () => {
      createComponent({ eventTypes: [6], filter: {} });

      expect(tokenTexts()).toEqual(['Merge request']);
    });

    it('lists the configured actions for merge_request (6)', () => {
      createComponent({
        eventTypes: [6],
        filter: {
          merge_request: {
            rules: [{ field: 'action', operator: 'in', value: ['ready', 'approved'] }],
          },
        },
      });

      expect(tokenTexts()).toEqual(['Merge request (Approved, Marked ready)']);
    });

    it('collapses event types 4, 5, and 6 into a single token', () => {
      createComponent({
        eventTypes: [4, 5, 6],
        filter: {
          merge_request: { rules: [{ field: 'action', operator: 'in', value: ['approved'] }] },
        },
      });

      expect(tokenTexts()).toEqual(['Merge request (Approved, Merge conflict, Marked ready)']);
    });
  });

  it('renders an "Unknown" token for an unrecognized event type', () => {
    createComponent({ eventTypes: [99], filter: {} });

    expect(tokenTexts()).toEqual(['Unknown']);
  });

  it('renders no tokens when there are no event types', () => {
    createComponent({ eventTypes: [], filter: {} });

    expect(findTokens()).toHaveLength(0);
  });

  it('renders no tokens when eventTypes is missing', () => {
    createComponent({});

    expect(findTokens()).toHaveLength(0);
  });
});
