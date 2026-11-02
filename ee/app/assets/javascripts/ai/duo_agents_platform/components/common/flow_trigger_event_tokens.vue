<script>
import { GlBadge, GlToken, GlTooltipDirective } from '@gitlab/ui';
import { FLOW_TRIGGER_TYPE_SCHEDULE } from 'ee/ai/duo_agents_platform/constants';
import { flowTriggerEventTokens } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'FlowTriggerEventTokens',
  components: {
    GlBadge,
    GlToken,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: {
    timezoneData: { default: () => [] },
  },
  props: {
    flowTrigger: {
      type: Object,
      required: true,
    },
  },
  SCHEDULE_EVENT_TYPE: FLOW_TRIGGER_TYPE_SCHEDULE.valueInt,
  computed: {
    tokens() {
      return flowTriggerEventTokens(this.flowTrigger, { timezoneData: this.timezoneData });
    },
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2 gl-whitespace-nowrap">
    <template v-for="token in tokens">
      <gl-token
        :key="token.eventType"
        v-gl-tooltip="token.tooltip"
        :tabindex="token.tooltip ? 0 : null"
        view-only
      >
        {{ token.text }}
      </gl-token>
      <gl-badge
        v-if="token.eventType === $options.SCHEDULE_EVENT_TYPE"
        :key="`${token.eventType}-beta`"
        data-testid="schedule-beta-badge"
      >
        {{ s__('DuoAgentsPlatform|Beta') }}
      </gl-badge>
    </template>
  </div>
</template>
