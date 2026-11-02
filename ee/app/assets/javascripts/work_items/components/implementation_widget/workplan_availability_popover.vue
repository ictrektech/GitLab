<script>
import { GlLink, GlPopover, GlSprintf } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'WorkplanAvailabilityPopover',
  components: { GlLink, GlPopover, GlSprintf },
  props: {
    target: {
      type: Function,
      required: true,
    },
    reason: {
      type: String,
      required: true,
    },
  },
  data() {
    return { containerId: uniqueId('workplan-availability-') };
  },
  workplanHelpPath: helpPagePath('user/work_items/workplan', {
    anchor: 'set-up-workplan-generation',
  }),
};
</script>

<template>
  <span :id="containerId">
    <gl-popover :target="target" :container="containerId" placement="bottom">
      <p class="gl-mb-0">
        <gl-sprintf :message="s__('AgentPlan|%{reason} %{linkStart}Learn more%{linkEnd}.')">
          <template #reason>{{ reason }}</template>
          <template #link="{ content }">
            <gl-link :href="$options.workplanHelpPath" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>
    </gl-popover>
  </span>
</template>
