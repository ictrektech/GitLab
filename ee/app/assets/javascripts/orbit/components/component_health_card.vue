<script>
import { defineComponent } from 'vue';
import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { s__ } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { STATUS_HEALTHY, STATUS_MIGRATING, COMPONENT_LABELS } from '../constants';

export default defineComponent({
  name: 'ComponentHealthCard',
  components: {
    GlIcon,
    GlLoadingIcon,
  },
  i18n: {
    inProgress: s__('Orbit|In progress'),
  },
  props: {
    component: {
      type: Object,
      required: true,
    },
  },
  computed: {
    isHealthy() {
      return this.component.state === STATUS_HEALTHY;
    },
    isMigrating() {
      return this.component.state === STATUS_MIGRATING;
    },
    displayName() {
      return COMPONENT_LABELS[this.component.name] || humanize(this.component.name);
    },
  },
});
</script>

<template>
  <div class="gl-border gl-flex-1 gl-rounded-md gl-border-default gl-bg-subtle gl-p-4">
    <div class="gl-flex gl-items-center gl-gap-3">
      <span
        v-if="isHealthy"
        class="gl-inline-block gl-h-3 gl-w-3 gl-shrink-0 gl-self-center gl-rounded-full gl-bg-status-success"
        aria-hidden="true"
        data-testid="healthy-dot"
      ></span>
      <gl-loading-icon v-else-if="isMigrating" size="sm" inline data-testid="migrating-icon" />
      <gl-icon
        v-else
        name="warning"
        variant="danger"
        :size="16"
        data-testid="unhealthy-warning-icon"
      />
      <span class="gl-font-bold">{{ displayName }}</span>
      <span v-if="isMigrating" class="gl-text-sm gl-text-subtle">{{
        $options.i18n.inProgress
      }}</span>
    </div>
  </div>
</template>
