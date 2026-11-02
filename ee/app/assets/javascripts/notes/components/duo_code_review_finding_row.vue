<script>
import { GlBadge, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { DUO_CODE_REVIEW_DEPTH_LABELS } from '../constants';

// Minor stays neutral because the info color already marks the targeted comment.
const SEVERITY_CONFIG = {
  critical: {
    message: s__('DuoCodeReview|%{severityStart}Critical finding:%{severityEnd} %{category}'),
    classes: 'gl-bg-feedback-danger gl-text-feedback-danger',
  },
  major: {
    message: s__('DuoCodeReview|%{severityStart}Major finding:%{severityEnd} %{category}'),
    classes: 'gl-bg-feedback-warning gl-text-feedback-warning',
  },
  minor: {
    message: s__('DuoCodeReview|%{severityStart}Minor finding:%{severityEnd} %{category}'),
    classes: 'gl-bg-subtle gl-text-default',
  },
};

export default {
  name: 'DuoCodeReviewFindingRow',
  components: {
    GlBadge,
    GlSprintf,
  },
  props: {
    finding: {
      type: Object,
      required: true,
    },
  },
  computed: {
    severityConfig() {
      return SEVERITY_CONFIG[this.finding.severity];
    },
    categoryLabel() {
      return humanize(this.finding.category, '[-_]');
    },
    depthLabel() {
      return DUO_CODE_REVIEW_DEPTH_LABELS[this.finding.depth];
    },
  },
};
</script>

<template>
  <div
    v-if="severityConfig"
    class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3 gl-py-3"
    :class="severityConfig.classes"
    data-testid="duo-code-review-finding-row"
  >
    <span data-testid="duo-code-review-finding-label">
      <gl-sprintf :message="severityConfig.message">
        <template #severity="{ content }">
          <span class="gl-font-bold">{{ content }}</span>
        </template>
        <template #category>{{ categoryLabel }}</template>
      </gl-sprintf>
    </span>
    <gl-badge v-if="depthLabel" variant="neutral" data-testid="duo-code-review-depth-badge">
      {{ depthLabel }}
    </gl-badge>
  </div>
</template>
