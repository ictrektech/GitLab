<script>
import { GlBadge } from '@gitlab/ui';
import { DUO_CODE_REVIEW_DEPTH_LABELS } from '../constants';

export default {
  name: 'DuoCodeReviewDepthBadge',
  components: {
    GlBadge,
  },
  props: {
    depth: {
      type: String,
      required: true,
    },
  },
  computed: {
    depthLabel() {
      return DUO_CODE_REVIEW_DEPTH_LABELS[this.depth];
    },
  },
};
</script>

<template>
  <gl-badge v-if="depthLabel" variant="neutral" data-testid="duo-code-review-depth-badge">
    {{ depthLabel }}
  </gl-badge>
</template>
