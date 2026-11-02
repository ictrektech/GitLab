<script>
import { GlAlert, GlCollapsibleListbox, GlFormGroup, GlFormInput, GlSprintf } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { formatTimezone, getWeekdayNames } from '~/lib/utils/datetime_utility';
import { __, s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import TimezoneDropdown from '~/vue_shared/components/timezone_dropdown/timezone_dropdown.vue';
import {
  FLOW_TRIGGER_TYPE_SCHEDULE,
  SCHEDULE_DAY_OF_MONTH_MAX,
  SCHEDULE_FIELD_DAY_OF_MONTH,
  SCHEDULE_FIELD_DAY_OF_WEEK,
  SCHEDULE_FIELD_HOUR,
  SCHEDULE_FIELD_MINUTE,
  SCHEDULE_FIELD_TIMEZONE,
  SCHEDULE_FREQUENCIES,
  SCHEDULE_FREQUENCY_FIELDS,
  SCHEDULE_HOUR_MAX,
  SCHEDULE_HOUR_MIN,
  SCHEDULE_MINUTE_VALUES,
} from 'ee/ai/duo_agents_platform/constants';
import {
  defaultScheduleTimezone,
  parseScheduleConfig,
  randomizeScheduleDefaults,
} from 'ee/ai/duo_agents_platform/utils';

const SCHEDULE_SCOPE = FLOW_TRIGGER_TYPE_SCHEDULE.value;

export default {
  name: 'ScheduleEventsConfiguration',
  components: {
    GlAlert,
    GlCollapsibleListbox,
    GlFormGroup,
    GlFormInput,
    GlSprintf,
    HelpPageLink,
    TimezoneDropdown,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: {
    timezoneData: {
      default: () => [],
    },
    userTimezone: {
      default: '',
    },
  },
  props: {
    value: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    invalidFeedback: {
      type: String,
      required: false,
      default: null,
    },
    serviceAccountRole: {
      type: String,
      required: false,
      default: null,
    },
    // The automation modal shows its own notice instead of the access warning.
    compact: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input'],
  data() {
    return {
      frequencyLabelId: uniqueId('schedule-frequency-label-'),
      dayLabelId: uniqueId('schedule-day-label-'),
      hourLabelId: uniqueId('schedule-hour-label-'),
      minuteLabelId: uniqueId('schedule-minute-label-'),
      timezoneLabelId: uniqueId('schedule-timezone-label-'),
      timezoneSearchTerm: '',
    };
  },
  computed: {
    runAtDescription() {
      return this.glFeatures.duoAutomations
        ? s__(
            'DuoAgentsPlatform|Automations might run a few minutes after the scheduled time to distribute load across the system.',
          )
        : s__(
            'DuoAgentsPlatform|Triggers might run a few minutes after the scheduled time to distribute load across the system.',
          );
    },
    schedule() {
      return parseScheduleConfig(this.value) ?? {};
    },
    frequency() {
      return this.schedule.frequency ?? null;
    },
    activeFields() {
      return SCHEDULE_FREQUENCY_FIELDS[this.frequency] ?? [];
    },
    showMinute() {
      return this.activeFields.includes(SCHEDULE_FIELD_MINUTE);
    },
    showHour() {
      return this.activeFields.includes(SCHEDULE_FIELD_HOUR);
    },
    showDayOfWeek() {
      return this.activeFields.includes(SCHEDULE_FIELD_DAY_OF_WEEK);
    },
    showDayOfMonth() {
      return this.activeFields.includes(SCHEDULE_FIELD_DAY_OF_MONTH);
    },
    showTimezone() {
      return this.activeFields.includes(SCHEDULE_FIELD_TIMEZONE);
    },
    showRunAt() {
      return this.showHour || this.showMinute;
    },
    frequencyToggleText() {
      return (
        SCHEDULE_FREQUENCIES.find((option) => option.value === this.frequency)?.text ??
        s__('DuoAgentsPlatform|Select frequency')
      );
    },
    dayOfWeekItems() {
      return getWeekdayNames().map((text, value) => ({ value, text }));
    },
    dayOfWeekToggleText() {
      return this.dayOfWeekItems[this.schedule.dayOfWeek]?.text ?? '';
    },
    dayOfMonthItems() {
      return Array.from({ length: SCHEDULE_DAY_OF_MONTH_MAX }, (_, index) => ({
        value: index + 1,
        text: String(index + 1),
      }));
    },
    dayOfMonthToggleText() {
      return this.schedule.dayOfMonth != null ? String(this.schedule.dayOfMonth) : '';
    },
    hourItems() {
      return Array.from({ length: SCHEDULE_HOUR_MAX - SCHEDULE_HOUR_MIN + 1 }, (_, index) => {
        const value = SCHEDULE_HOUR_MIN + index;
        return { value, text: String(value).padStart(2, '0') };
      });
    },
    hourToggleText() {
      return String(this.schedule.hour ?? 0).padStart(2, '0');
    },
    minuteItems() {
      return SCHEDULE_MINUTE_VALUES.map((value) => ({
        value,
        text: String(value).padStart(2, '0'),
      }));
    },
    minuteToggleText() {
      return String(this.schedule.minute ?? 0).padStart(2, '0');
    },
    timezoneItems() {
      const term = this.timezoneSearchTerm.toLowerCase();

      return this.timezoneData
        .map((timezone) => ({ value: timezone.identifier, text: formatTimezone(timezone) }))
        .filter(({ text }) => text.toLowerCase().includes(term));
    },
    timezoneText() {
      const timezone = this.timezoneData.find((tz) => tz.identifier === this.schedule.timezone);
      return timezone ? formatTimezone(timezone) : this.schedule.timezone || __('Select timezone');
    },
    defaultTimezone() {
      return defaultScheduleTimezone(this.timezoneData, this.userTimezone);
    },
  },
  methods: {
    emitSchedule(nextSchedule) {
      this.$emit('input', { ...this.value, [SCHEDULE_SCOPE]: nextSchedule });
    },
    patchSchedule(patch) {
      this.emitSchedule({ ...this.schedule, ...patch });
    },
    onSelectFrequency(frequency) {
      this.emitSchedule(randomizeScheduleDefaults(frequency, { timezone: this.defaultTimezone }));
    },
    onSelectHour(hour) {
      this.patchSchedule({ hour });
    },
    // An empty or fractional entry clears the hour, so the existing validation reports it.
    onInputHour(value) {
      const hour = value === '' ? null : Number(value);
      this.patchSchedule({ hour: Number.isInteger(hour) ? hour : null });
    },
    onSelectMinute(minute) {
      this.patchSchedule({ minute });
    },
    onSelectDayOfWeek(dayOfWeek) {
      this.patchSchedule({ dayOfWeek });
    },
    onSelectDayOfMonth(dayOfMonth) {
      this.patchSchedule({ dayOfMonth });
    },
    onSelectTimezone(timezone) {
      this.patchSchedule({ timezone: timezone.identifier });
    },
  },
  scheduleWarningRoleLinkText: s__('DuoAgentsPlatform|%{role} role'),
  SCHEDULE_FREQUENCIES,
  SCHEDULE_HOUR_MIN,
  SCHEDULE_HOUR_MAX,
};
</script>

<template>
  <div
    class="gl-flex"
    :class="compact ? 'gl-flex-wrap gl-items-center gl-gap-x-4 gl-gap-y-3' : 'gl-flex-col gl-gap-4'"
  >
    <gl-alert
      v-if="!compact && !glFeatures.duoAutomations"
      data-testid="schedule-access-warning"
      variant="warning"
      :dismissible="false"
    >
      <gl-sprintf
        v-if="serviceAccountRole"
        :message="
          s__(
            `DuoAgentsPlatform|Scheduled triggers do not use composite identity. They run with the service account's %{linkStart}%{role} role%{linkEnd} on this project.`,
          )
        "
      >
        <template #link>
          <help-page-link href="user/permissions" anchor="roles">
            <gl-sprintf :message="$options.scheduleWarningRoleLinkText">
              <template #role>{{ serviceAccountRole }}</template>
            </gl-sprintf>
          </help-page-link>
        </template>
      </gl-sprintf>
      <template v-else>{{
        s__(
          `DuoAgentsPlatform|Scheduled triggers do not use composite identity. They run with only the service account's permissions.`,
        )
      }}</template>
    </gl-alert>
    <p
      v-else-if="!compact"
      class="gl-border gl-mb-0 gl-rounded-lg gl-border-subtle gl-bg-subtle gl-px-4 gl-py-3 gl-text-subtle"
      data-testid="schedule-safe-use-notice"
    >
      {{
        s__(
          'DuoAgentsPlatform|Scheduled runs are unattended and use only service account permissions.',
        )
      }}
      <help-page-link href="user/duo_agent_platform/security_threats">{{
        s__('DuoAgentsPlatform|See safe use guide')
      }}</help-page-link>
    </p>

    <gl-form-group
      :label="compact ? null : s__('DuoAgentsPlatform|Frequency')"
      :state="!invalidFeedback"
      :invalid-feedback="invalidFeedback"
      class="!gl-mb-0"
    >
      <span v-if="compact" :id="frequencyLabelId" class="gl-sr-only">{{
        s__('DuoAgentsPlatform|Frequency')
      }}</span>
      <gl-collapsible-listbox
        :items="$options.SCHEDULE_FREQUENCIES"
        :selected="frequency"
        :toggle-text="frequencyToggleText"
        :header-text="s__('DuoAgentsPlatform|Select frequency')"
        :toggle-aria-labelled-by="compact ? frequencyLabelId : null"
        data-testid="frequency-listbox"
        :block="!compact"
        @select="onSelectFrequency"
      />
    </gl-form-group>

    <gl-form-group
      v-if="showDayOfWeek"
      :label="compact ? null : s__('DuoAgentsPlatform|Run on')"
      class="!gl-mb-0"
    >
      <div class="gl-flex gl-items-center gl-gap-3">
        <span v-if="compact" :id="dayLabelId" class="gl-sr-only">{{
          s__('DuoAgentsPlatform|Run on')
        }}</span>
        <gl-collapsible-listbox
          :items="dayOfWeekItems"
          :selected="schedule.dayOfWeek"
          :toggle-text="dayOfWeekToggleText"
          :header-text="s__('DuoAgentsPlatform|Select day of the week')"
          :toggle-aria-labelled-by="compact ? dayLabelId : null"
          data-testid="day-of-week-listbox"
          @select="onSelectDayOfWeek"
        />
        <span class="gl-text-subtle">{{ s__('DuoAgentsPlatform|of each week') }}</span>
      </div>
    </gl-form-group>

    <gl-form-group
      v-if="showDayOfMonth"
      :label="compact ? null : s__('DuoAgentsPlatform|Run on')"
      class="!gl-mb-0"
    >
      <div class="gl-flex gl-items-center gl-gap-3">
        <span v-if="compact" :id="dayLabelId" class="gl-sr-only">{{
          s__('DuoAgentsPlatform|Run on')
        }}</span>
        <gl-collapsible-listbox
          :items="dayOfMonthItems"
          :selected="schedule.dayOfMonth"
          :toggle-text="dayOfMonthToggleText"
          :header-text="s__('DuoAgentsPlatform|Select day of the month')"
          :toggle-aria-labelled-by="compact ? dayLabelId : null"
          data-testid="day-of-month-listbox"
          @select="onSelectDayOfMonth"
        />
        <span class="gl-text-subtle">{{ s__('DuoAgentsPlatform|of each month') }}</span>
      </div>
    </gl-form-group>

    <gl-form-group
      v-if="showRunAt"
      :label="compact ? null : s__('DuoAgentsPlatform|Run at')"
      :description="compact ? null : runAtDescription"
      class="!gl-mb-0"
    >
      <div class="gl-flex gl-items-center gl-gap-2">
        <template v-if="showHour">
          <gl-form-input
            v-if="compact"
            :value="schedule.hour"
            :aria-label="s__('DuoAgentsPlatform|Hour (24-hour)')"
            type="number"
            :min="$options.SCHEDULE_HOUR_MIN"
            :max="$options.SCHEDULE_HOUR_MAX"
            width="xs"
            data-testid="hour-input"
            @input="onInputHour"
          />
          <span v-else :id="hourLabelId" class="gl-sr-only">{{
            s__('DuoAgentsPlatform|Hour (24-hour)')
          }}</span>
          <gl-collapsible-listbox
            v-if="!compact"
            :items="hourItems"
            :selected="schedule.hour"
            :toggle-text="hourToggleText"
            :toggle-aria-labelled-by="hourLabelId"
            :header-text="s__('DuoAgentsPlatform|Select hour')"
            data-testid="hour-listbox"
            @select="onSelectHour"
          />
          <span aria-hidden="true">:</span>
        </template>
        <span :id="minuteLabelId" class="gl-sr-only">{{ __('Minute') }}</span>
        <gl-collapsible-listbox
          :items="minuteItems"
          :selected="schedule.minute"
          :toggle-text="minuteToggleText"
          :toggle-aria-labelled-by="minuteLabelId"
          :header-text="s__('DuoAgentsPlatform|Select minute')"
          data-testid="minute-listbox"
          @select="onSelectMinute"
        />
        <span v-if="!showHour" class="gl-text-subtle">{{
          s__('DuoAgentsPlatform|minutes past the hour')
        }}</span>
      </div>
    </gl-form-group>

    <div v-if="compact && showTimezone" class="gl-flex gl-w-full gl-items-center gl-gap-2">
      <span class="gl-text-subtle" data-testid="schedule-timezone-text">{{ timezoneText }}</span>
      <span aria-hidden="true" class="gl-text-subtle">&middot;</span>
      <span :id="timezoneLabelId" class="gl-sr-only">{{
        s__('DuoAgentsPlatform|Change time zone')
      }}</span>
      <gl-collapsible-listbox
        :items="timezoneItems"
        :selected="schedule.timezone"
        :toggle-text="s__('DuoAgentsPlatform|Change')"
        :toggle-aria-labelled-by="timezoneLabelId"
        :header-text="__('Select timezone')"
        category="tertiary"
        variant="link"
        no-caret
        searchable
        fluid-width
        data-testid="timezone-listbox"
        @search="timezoneSearchTerm = $event.trim()"
        @select="patchSchedule({ timezone: $event })"
      />
    </div>
    <gl-form-group v-else-if="showTimezone" :label="__('Time zone')" class="!gl-mb-0">
      <timezone-dropdown
        :value="schedule.timezone || ''"
        :timezone-data="timezoneData"
        :header-text="__('Select timezone')"
        @input="onSelectTimezone"
      />
    </gl-form-group>
  </div>
</template>
