<script>
import { GlButton, GlLink } from '@gitlab/ui';

export default {
  name: 'GeoSiteReplicableTitle',
  components: {
    GlButton,
    GlLink,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    expanded: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['toggle'],
  computed: {
    chevronIcon() {
      return this.expanded ? 'chevron-down' : 'chevron-right';
    },
    ariaExpanded() {
      return this.expanded ? 'true' : 'false';
    },
  },
};
</script>

<template>
  <gl-button
    v-if="item.children"
    class="!gl-p-0"
    category="tertiary"
    variant="confirm"
    :icon="chevronIcon"
    :aria-expanded="ariaExpanded"
    data-testid="replicable-group-toggle"
    @click="$emit('toggle')"
  >
    {{ item.titlePlural }}
  </gl-button>
  <gl-link v-else-if="item.replicationView" :href="item.replicationView">{{
    item.titlePlural
  }}</gl-link>
  <span v-else>{{ item.titlePlural }}</span>
</template>
