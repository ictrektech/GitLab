<script>
import {
  GlBadge,
  GlDisclosureDropdown,
  GlIcon,
  GlLink,
  GlToggle,
  GlTooltipDirective,
  GlTruncate,
} from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import timeagoMixin from '~/vue_shared/mixins/timeago';
import {
  AUTOMATION_RUN_STATUS_META,
  AUTOMATION_RUN_STATUS_NEVER,
} from 'ee/ai/duo_agents_platform/constants';
import {
  FLOW_TRIGGERS_EDIT_ROUTE,
  FLOW_TRIGGERS_SHOW_ROUTE,
} from 'ee/ai/duo_agents_platform/router/constants';
import {
  automationSharedGoal,
  flowTriggerEventLabels,
  scheduleSummaryLabels,
} from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AutomationRow',
  components: {
    GlBadge,
    GlDisclosureDropdown,
    GlIcon,
    GlLink,
    GlToggle,
    GlTruncate,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glAbilitiesMixin(), timeagoMixin],
  inject: {
    timezoneData: { default: () => [] },
  },
  props: {
    automation: {
      type: Object,
      required: true,
    },
    isToggling: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSelected: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['delete', 'edit', 'toggle'],
  computed: {
    lastRun() {
      return this.automation.lastRun;
    },
    lastRunStatus() {
      return AUTOMATION_RUN_STATUS_META[this.lastRun?.status ?? AUTOMATION_RUN_STATUS_NEVER];
    },
    lastRunTooltip() {
      if (!this.lastRun) return null;

      const { startedAt, finishedAt } = this.lastRun;
      const message = finishedAt
        ? s__('DuoAgentsPlatform|Finished %{timeAgo}')
        : s__('DuoAgentsPlatform|Started %{timeAgo}');

      return sprintf(message, { timeAgo: this.timeFormatted(finishedAt ?? startedAt) });
    },
    runningSessions() {
      const count = this.automation.runningCount;
      if (!count) return null;

      return sprintf(
        n__('DuoAgentsPlatform|%{count} session', 'DuoAgentsPlatform|%{count} sessions', count),
        { count },
      );
    },
    showRoute() {
      return {
        name: FLOW_TRIGGERS_SHOW_ROUTE,
        params: { id: getIdFromGraphQLId(this.automation.id) },
        query: this.$route.query,
      };
    },
    schedule() {
      return scheduleSummaryLabels(this.automation.filter, this.timezoneData)[0];
    },
    conditions() {
      return this.schedule ?? flowTriggerEventLabels(this.automation).join(', ');
    },
    // The modal edits one goal for the whole automation.
    canEditInModal() {
      return automationSharedGoal(this.automation) !== null;
    },
    actionItems() {
      return [
        {
          text: s__('DuoAgentsPlatform|Edit automation'),
          ...(this.canEditInModal
            ? { action: () => this.$emit('edit', this.automation) }
            : {
                to: {
                  name: FLOW_TRIGGERS_EDIT_ROUTE,
                  params: { id: getIdFromGraphQLId(this.automation.id) },
                },
              }),
        },
        {
          text: s__('DuoAgentsPlatform|Delete automation'),
          action: () => this.$emit('delete', this.automation.id),
          variant: 'danger',
        },
      ];
    },
    toggleLabel() {
      return sprintf(
        s__('DuoAgentsPlatform|Turn automation on or off: %{description}'),
        { description: this.automation.description },
        false,
      );
    },
  },
};
</script>

<template>
  <li
    class="gl-border-b gl-relative gl-flex gl-items-start gl-justify-between gl-gap-3 gl-px-5 gl-py-3"
    :class="isSelected ? 'gl-bg-strong' : 'hover:gl-bg-subtle'"
  >
    <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col gl-gap-2">
      <gl-link
        :to="showRoute"
        class="gl-self-start gl-font-bold !gl-text-default !gl-no-underline gl-stretched-link"
        :data-automation-id="automation.id"
        data-testid="automation-description"
      >
        {{ automation.description }}
      </gl-link>
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-2 gl-text-subtle">
        <gl-badge
          v-gl-tooltip.viewport
          :variant="lastRunStatus.variant"
          :icon="lastRunStatus.icon"
          icon-size="sm"
          :title="lastRunTooltip"
          :tabindex="lastRun ? 0 : null"
          class="gl-relative gl-shrink-0"
        >
          {{ lastRunStatus.text }}
        </gl-badge>
        <span v-if="runningSessions" class="gl-shrink-0" data-testid="automation-running-sessions">
          {{ runningSessions }}
        </span>
        <gl-truncate
          v-else-if="lastRun && lastRun.error"
          :text="lastRun.error"
          with-tooltip
          tabindex="0"
          class="gl-relative"
          data-testid="automation-last-run-error"
        />
      </span>
      <span
        v-if="conditions"
        class="gl-flex gl-min-w-0 gl-items-center gl-gap-2 gl-text-subtle"
        data-testid="automation-conditions"
      >
        <gl-icon :name="schedule ? 'clock' : 'trigger-source'" class="gl-shrink-0" />
        <gl-truncate :text="conditions" with-tooltip />
        <gl-badge v-if="schedule" class="gl-shrink-0" data-testid="automation-schedule-beta-badge">
          {{ s__('DuoAgentsPlatform|Beta') }}
        </gl-badge>
      </span>
    </div>

    <div class="gl-relative gl-flex gl-shrink-0 gl-items-center gl-gap-3">
      <gl-toggle
        :value="automation.active"
        :is-loading="isToggling"
        :disabled="!glAbilities.manageAiFlowTriggers"
        :label="toggleLabel"
        label-position="hidden"
        @change="$emit('toggle', { id: automation.id, active: $event })"
      />
      <gl-disclosure-dropdown
        v-if="glAbilities.manageAiFlowTriggers"
        :items="actionItems"
        :toggle-text="__('More actions')"
        text-sr-only
        icon="ellipsis_v"
        category="tertiary"
        no-caret
        placement="bottom-end"
      />
    </div>
  </li>
</template>
