import { GlFormGroup, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScheduleEventsConfiguration from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/schedule_events_configuration.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import TimezoneDropdown from '~/vue_shared/components/timezone_dropdown/timezone_dropdown.vue';
import {
  FLOW_TRIGGER_TYPE_SCHEDULE,
  SCHEDULE_FREQUENCIES,
  SCHEDULE_FREQUENCY_EVERY_15_MINUTES,
  SCHEDULE_FREQUENCY_EVERY_30_MINUTES,
  SCHEDULE_FREQUENCY_HOURLY,
  SCHEDULE_FREQUENCY_DAILY,
  SCHEDULE_FREQUENCY_WEEKDAYS,
  SCHEDULE_FREQUENCY_WEEKLY,
  SCHEDULE_FREQUENCY_MONTHLY,
} from 'ee/ai/duo_agents_platform/constants';

const SCOPE = FLOW_TRIGGER_TYPE_SCHEDULE.value;
const USER_TIMEZONE = 'America/Chicago';
const TIMEZONE_DATA = [
  { identifier: 'America/Chicago', name: 'Central Time (US & Canada)', offset: -21600 },
  { identifier: 'Etc/UTC', name: 'UTC', offset: 0 },
];

describe('ScheduleEventsConfiguration', () => {
  let wrapper;

  const findFrequencyListbox = () => wrapper.findComponentByTestId('frequency-listbox');
  const findDayOfWeekListbox = () => wrapper.findComponentByTestId('day-of-week-listbox');
  const findDayOfMonthListbox = () => wrapper.findComponentByTestId('day-of-month-listbox');
  const findHourListbox = () => wrapper.findComponentByTestId('hour-listbox');
  const findMinuteListbox = () => wrapper.findComponentByTestId('minute-listbox');
  const findTimezoneDropdown = () => wrapper.findComponent(TimezoneDropdown);
  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findAccessWarning = () => wrapper.findComponentByTestId('schedule-access-warning');
  const findAccessWarningRoleLink = () => findAccessWarning().findComponent(HelpPageLink);
  const findSafeUseNotice = () => wrapper.findByTestId('schedule-safe-use-notice');
  const findHourInput = () => wrapper.findComponentByTestId('hour-input');

  const filterFor = (schedule) => ({ [SCOPE]: schedule });
  const lastEmittedSchedule = () => {
    const calls = wrapper.emitted('input');
    return calls[calls.length - 1][0][SCOPE];
  };

  const createWrapper = (props = {}, provide = {}, stubs = {}) => {
    wrapper = shallowMountExtended(ScheduleEventsConfiguration, {
      propsData: { value: {}, ...props },
      provide: { timezoneData: TIMEZONE_DATA, userTimezone: USER_TIMEZONE, ...provide },
      stubs,
    });
  };

  describe('access warning', () => {
    it('renders as a non-dismissible warning', () => {
      createWrapper();

      expect(findAccessWarning().props('variant')).toBe('warning');
      expect(findAccessWarning().props('dismissible')).toBe(false);
    });

    it('shows the composite identity warning', () => {
      createWrapper();

      expect(findAccessWarning().text()).toBe(
        "Scheduled triggers do not use composite identity. They run with only the service account's permissions.",
      );
    });

    it('keeps the warning visible once a frequency is selected', () => {
      createWrapper({ value: filterFor({ frequency: SCHEDULE_FREQUENCY_HOURLY }) });

      expect(findAccessWarning().exists()).toBe(true);
    });

    describe('when a service account role is provided', () => {
      beforeEach(() => {
        createWrapper({ serviceAccountRole: 'Developer' }, {}, { GlSprintf, HelpPageLink });
      });

      it('names the role in the warning', () => {
        expect(findAccessWarning().text()).toBe(
          "Scheduled triggers do not use composite identity. They run with the service account's Developer role on this project.",
        );
      });

      it('links the role to the roles documentation', () => {
        expect(findAccessWarningRoleLink().props('href')).toBe('user/permissions');
        expect(findAccessWarningRoleLink().props('anchor')).toBe('roles');
        expect(findAccessWarningRoleLink().text()).toBe('Developer role');
      });
    });

    describe('when no service account role is provided', () => {
      beforeEach(() => {
        createWrapper({ serviceAccountRole: null }, {}, { GlSprintf, HelpPageLink });
      });

      it('shows the generic warning without a role link', () => {
        expect(findAccessWarning().text()).toBe(
          "Scheduled triggers do not use composite identity. They run with only the service account's permissions.",
        );
        expect(findAccessWarningRoleLink().exists()).toBe(false);
      });
    });
  });

  describe('frequency selection', () => {
    it('renders the frequency listbox with the seven presets and a placeholder', () => {
      createWrapper();

      expect(findFrequencyListbox().props('items')).toBe(SCHEDULE_FREQUENCIES);
      expect(findFrequencyListbox().props('toggleText')).toBe('Select frequency');
    });

    it('renders no contextual pickers before a frequency is selected', () => {
      createWrapper();

      expect(findHourListbox().exists()).toBe(false);
      expect(findMinuteListbox().exists()).toBe(false);
      expect(findTimezoneDropdown().exists()).toBe(false);
      expect(findDayOfWeekListbox().exists()).toBe(false);
      expect(findDayOfMonthListbox().exists()).toBe(false);
    });

    describe('with randomization stubbed to its lowest values', () => {
      beforeEach(() => {
        jest.spyOn(Math, 'random').mockReturnValue(0);
      });

      it('populates daily defaults and the user timezone on selection', () => {
        createWrapper();

        findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_DAILY);

        expect(lastEmittedSchedule()).toEqual({
          frequency: SCHEDULE_FREQUENCY_DAILY,
          minute: 0,
          hour: 0,
          timezone: USER_TIMEZONE,
        });
      });

      it('adds a randomized day-of-week for the weekly preset', () => {
        createWrapper();

        findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_WEEKLY);

        expect(lastEmittedSchedule()).toEqual({
          frequency: SCHEDULE_FREQUENCY_WEEKLY,
          minute: 0,
          hour: 0,
          dayOfWeek: 0,
          timezone: USER_TIMEZONE,
        });
      });

      it('adds a randomized day-of-month for the monthly preset', () => {
        createWrapper();

        findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_MONTHLY);

        expect(lastEmittedSchedule()).toEqual({
          frequency: SCHEDULE_FREQUENCY_MONTHLY,
          minute: 0,
          hour: 0,
          dayOfMonth: 1,
          timezone: USER_TIMEZONE,
        });
      });

      it('only stores the frequency for sub-hour presets', () => {
        createWrapper();

        findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_EVERY_15_MINUTES);

        expect(lastEmittedSchedule()).toEqual({ frequency: SCHEDULE_FREQUENCY_EVERY_15_MINUTES });
      });

      it('preserves other filter scopes when selecting a frequency', () => {
        const otherScope = { pipeline_hooks: { rules: [] } };
        createWrapper({ value: { ...otherScope } });

        findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_DAILY);

        expect(wrapper.emitted('input')[0][0].pipeline_hooks).toEqual(otherScope.pipeline_hooks);
      });
    });
  });

  describe('contextual pickers per frequency', () => {
    it.each`
      frequency                              | hour     | minute   | dayOfWeek | dayOfMonth | timezone
      ${SCHEDULE_FREQUENCY_EVERY_15_MINUTES} | ${false} | ${false} | ${false}  | ${false}   | ${false}
      ${SCHEDULE_FREQUENCY_EVERY_30_MINUTES} | ${false} | ${false} | ${false}  | ${false}   | ${false}
      ${SCHEDULE_FREQUENCY_HOURLY}           | ${false} | ${true}  | ${false}  | ${false}   | ${true}
      ${SCHEDULE_FREQUENCY_DAILY}            | ${true}  | ${true}  | ${false}  | ${false}   | ${true}
      ${SCHEDULE_FREQUENCY_WEEKDAYS}         | ${true}  | ${true}  | ${false}  | ${false}   | ${true}
      ${SCHEDULE_FREQUENCY_WEEKLY}           | ${true}  | ${true}  | ${true}   | ${false}   | ${true}
      ${SCHEDULE_FREQUENCY_MONTHLY}          | ${true}  | ${true}  | ${false}  | ${true}    | ${true}
    `(
      'shows the expected pickers for $frequency',
      ({ frequency, hour, minute, dayOfWeek, dayOfMonth, timezone }) => {
        createWrapper({ value: filterFor({ frequency }) });

        expect(findHourListbox().exists()).toBe(hour);
        expect(findMinuteListbox().exists()).toBe(minute);
        expect(findDayOfWeekListbox().exists()).toBe(dayOfWeek);
        expect(findDayOfMonthListbox().exists()).toBe(dayOfMonth);
        expect(findTimezoneDropdown().exists()).toBe(timezone);
      },
    );

    it('explains the standalone minute picker when no hour is shown', () => {
      createWrapper({ value: filterFor({ frequency: SCHEDULE_FREQUENCY_HOURLY }) });

      expect(wrapper.text()).toContain('minutes past the hour');
    });

    it('omits the minutes-past-the-hour hint when an hour is shown', () => {
      createWrapper({ value: filterFor({ frequency: SCHEDULE_FREQUENCY_DAILY }) });

      expect(wrapper.text()).not.toContain('minutes past the hour');
    });
  });

  describe('pre-filling existing values', () => {
    beforeEach(() => {
      createWrapper({
        value: filterFor({
          frequency: SCHEDULE_FREQUENCY_MONTHLY,
          minute: 30,
          hour: 14,
          dayOfMonth: 12,
          timezone: 'Etc/UTC',
        }),
      });
    });

    it('selects the stored frequency', () => {
      expect(findFrequencyListbox().props('selected')).toBe(SCHEDULE_FREQUENCY_MONTHLY);
    });

    it('offers every hour of the 24-hour clock, zero-padded', () => {
      const items = findHourListbox().props('items');

      expect(items).toHaveLength(24);
      expect(items[0]).toEqual({ value: 0, text: '00' });
      expect(items[23]).toEqual({ value: 23, text: '23' });
    });

    it('selects the stored hour and shows it as a 24-hour value', () => {
      expect(findHourListbox().props('selected')).toBe(14);
      expect(findHourListbox().props('toggleText')).toBe('14');
    });

    it('labels the hour listbox via a dedicated sr-only label', () => {
      const label = wrapper.find(`#${findHourListbox().props('toggleAriaLabelledBy')}`);

      expect(label.classes()).toContain('gl-sr-only');
      expect(label.text()).toBe('Hour (24-hour)');
    });

    it('selects the stored minute and zero-pads the toggle text', () => {
      expect(findMinuteListbox().props('selected')).toBe(30);
      expect(findMinuteListbox().props('toggleText')).toBe('30');
    });

    it('labels the minute listbox via a dedicated sr-only label', () => {
      const label = wrapper.find(`#${findMinuteListbox().props('toggleAriaLabelledBy')}`);

      expect(label.classes()).toContain('gl-sr-only');
      expect(label.text()).toBe('Minute');
    });

    it('passes the stored timezone and the injected timezone data to the dropdown', () => {
      expect(findTimezoneDropdown().props('value')).toBe('Etc/UTC');
      expect(findTimezoneDropdown().props('timezoneData')).toBe(TIMEZONE_DATA);
    });

    it('selects the stored day-of-month', () => {
      expect(findDayOfMonthListbox().props('selected')).toBe(12);
    });
  });

  describe('editing a configured schedule', () => {
    beforeEach(() => {
      createWrapper({
        value: filterFor({
          frequency: SCHEDULE_FREQUENCY_WEEKLY,
          minute: 0,
          hour: 9,
          dayOfWeek: 1,
          timezone: USER_TIMEZONE,
        }),
      });
    });

    it('emits the selected hour', () => {
      findHourListbox().vm.$emit('select', 17);

      expect(lastEmittedSchedule().hour).toBe(17);
    });

    it('emits the selected minute', () => {
      findMinuteListbox().vm.$emit('select', 45);

      expect(lastEmittedSchedule().minute).toBe(45);
    });

    it('emits the selected day-of-week', () => {
      findDayOfWeekListbox().vm.$emit('select', 4);

      expect(lastEmittedSchedule().dayOfWeek).toBe(4);
    });

    it('emits the selected day-of-month', () => {
      createWrapper({
        value: filterFor({ frequency: SCHEDULE_FREQUENCY_MONTHLY, dayOfMonth: 12 }),
      });

      findDayOfMonthListbox().vm.$emit('select', 25);

      expect(lastEmittedSchedule().dayOfMonth).toBe(25);
    });

    it('emits the identifier of the selected timezone', () => {
      findTimezoneDropdown().vm.$emit('input', { identifier: 'Etc/UTC', name: 'UTC' });

      expect(lastEmittedSchedule().timezone).toBe('Etc/UTC');
    });
  });

  describe('timezone defaulting', () => {
    const selectDaily = () => findFrequencyListbox().vm.$emit('select', SCHEDULE_FREQUENCY_DAILY);

    it('prefers a selectable profile timezone over the browser timezone', () => {
      jest
        .spyOn(Intl, 'DateTimeFormat')
        .mockReturnValue({ resolvedOptions: () => ({ timeZone: 'Etc/UTC' }) });
      createWrapper({}, { userTimezone: 'America/Chicago' });

      selectDaily();

      expect(lastEmittedSchedule().timezone).toBe('America/Chicago');
    });

    it('falls back to the browser timezone when no profile timezone is set', () => {
      jest
        .spyOn(Intl, 'DateTimeFormat')
        .mockReturnValue({ resolvedOptions: () => ({ timeZone: 'Etc/UTC' }) });
      createWrapper({}, { userTimezone: '' });

      selectDaily();

      expect(lastEmittedSchedule().timezone).toBe('Etc/UTC');
    });

    it('falls back to the browser timezone when the profile timezone is absent from the dropdown data', () => {
      jest
        .spyOn(Intl, 'DateTimeFormat')
        .mockReturnValue({ resolvedOptions: () => ({ timeZone: 'Etc/UTC' }) });
      createWrapper({}, { userTimezone: 'Antarctica/Troll' });

      selectDaily();

      expect(lastEmittedSchedule().timezone).toBe('Etc/UTC');
    });

    it('falls back to UTC when the browser zone is absent from the dropdown data', () => {
      jest
        .spyOn(Intl, 'DateTimeFormat')
        .mockReturnValue({ resolvedOptions: () => ({ timeZone: 'Antarctica/Troll' }) });
      createWrapper({}, { userTimezone: '' });

      selectDaily();

      expect(lastEmittedSchedule().timezone).toBe('Etc/UTC');
    });

    it('leaves the timezone empty when UTC is also absent from the dropdown data', () => {
      jest
        .spyOn(Intl, 'DateTimeFormat')
        .mockReturnValue({ resolvedOptions: () => ({ timeZone: 'Antarctica/Troll' }) });
      createWrapper(
        {},
        {
          userTimezone: '',
          timezoneData: [
            { identifier: 'America/Chicago', name: 'Central Time (US & Canada)', offset: -21600 },
          ],
        },
      );

      selectDaily();

      expect(lastEmittedSchedule().timezone).toBe('');
    });
  });

  describe('when duoAutomations is enabled', () => {
    beforeEach(() => {
      createWrapper({ serviceAccountRole: 'Developer' }, { glFeatures: { duoAutomations: true } });
    });

    it('replaces the access warning with the safe use notice', () => {
      expect(findAccessWarning().exists()).toBe(false);
      expect(findSafeUseNotice().text()).toMatchInterpolatedText(
        'Scheduled runs are unattended and use only service account permissions. See safe use guide',
      );
      expect(findSafeUseNotice().findComponent(HelpPageLink).props('href')).toBe(
        'user/duo_agent_platform/security_threats',
      );
    });
  });

  describe('invalidFeedback prop', () => {
    it('keeps the frequency group valid when invalidFeedback is null', () => {
      createWrapper();

      expect(findFormGroup().attributes('state')).toBe('true');
      expect(findFormGroup().attributes('invalid-feedback')).toBeUndefined();
    });

    it('marks the frequency group invalid and shows the message when invalidFeedback is set', () => {
      const message = 'Configure the schedule.';
      createWrapper({ invalidFeedback: message });

      expect(findFormGroup().attributes('state')).toBeUndefined();
      expect(findFormGroup().attributes('invalid-feedback')).toBe(message);
    });
  });

  describe('when compact', () => {
    const createCompact = (timezone = 'Etc/UTC') =>
      createWrapper(
        {
          compact: true,
          value: filterFor({ frequency: SCHEDULE_FREQUENCY_WEEKLY, hour: 9, timezone }),
        },
        { glFeatures: { duoAutomations: true } },
      );

    it('hides the safe use notice, labels and the time zone dropdown', () => {
      createCompact();

      expect(findSafeUseNotice().exists()).toBe(false);
      expect(findFormGroup().attributes('label')).toBeUndefined();
      expect(findTimezoneDropdown().exists()).toBe(false);
    });

    it.each`
      findListbox             | name
      ${findFrequencyListbox} | ${'Frequency'}
      ${findDayOfWeekListbox} | ${'Run on'}
    `('names the $name listbox with a hidden label', ({ findListbox, name }) => {
      createCompact();

      const labelId = findListbox().props('toggleAriaLabelledBy');

      expect(wrapper.find(`#${labelId}`).text()).toBe(name);
    });

    it('enters the hour in a labelled number input instead of a listbox', () => {
      createCompact();

      expect(findHourListbox().exists()).toBe(false);
      expect(findHourInput().attributes()).toMatchObject({
        'aria-label': 'Hour (24-hour)',
        type: 'number',
        min: '0',
        max: '23',
        value: '9',
      });
    });

    it.each`
      input    | hour
      ${'0'}   | ${0}
      ${'17'}  | ${17}
      ${''}    | ${null}
      ${'7.5'} | ${null}
    `('emits hour $hour when $input is entered', ({ input, hour }) => {
      createCompact();

      findHourInput().vm.$emit('input', input);

      expect(lastEmittedSchedule().hour).toBe(hour);
    });

    it.each`
      timezone        | text
      ${'Etc/UTC'}    | ${'[UTC 0] UTC'}
      ${'Asia/Tokyo'} | ${'Asia/Tokyo'}
      ${''}           | ${'Select timezone'}
    `('shows $timezone as $text', ({ timezone, text }) => {
      createCompact(timezone);

      expect(wrapper.findByTestId('schedule-timezone-text').text()).toBe(text);
    });

    it('changes the time zone from the inline picker', () => {
      createCompact();

      wrapper.findComponentByTestId('timezone-listbox').vm.$emit('select', 'America/Chicago');

      expect(lastEmittedSchedule().timezone).toBe('America/Chicago');
    });
  });
});
