<script>
import { GlIcon, GlPopover, GlSprintf } from '@gitlab/ui';
import { n__, sprintf } from '~/locale';
import {
  HEALTH_STATUS_AT_RISK,
  HEALTH_STATUS_NEEDS_ATTENTION,
  HEALTH_STATUS_ON_TRACK,
} from 'ee/sidebar/constants';

export default {
  name: 'WorkItemRolledUpHealthStatus',
  components: {
    GlIcon,
    GlPopover,
    GlSprintf,
  },
  props: {
    rolledUpHealthStatus: {
      type: Array,
      required: true,
    },
    healthStatusVisible: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    rolledUpOnTrackWorkItems() {
      return this.rolledUpHealthStatus?.find(
        (status) => status.healthStatus === HEALTH_STATUS_ON_TRACK,
      );
    },
    rolledUpAtRiskWorkItems() {
      return this.rolledUpHealthStatus?.find(
        (status) => status.healthStatus === HEALTH_STATUS_AT_RISK,
      );
    },
    rolledUpNeedsAttentionWorkItems() {
      return this.rolledUpHealthStatus?.find(
        (status) => status.healthStatus === HEALTH_STATUS_NEEDS_ATTENTION,
      );
    },
    showRolledUpHealthStatus() {
      return (
        this.rolledUpOnTrackWorkItems?.count ||
        this.rolledUpAtRiskWorkItems?.count ||
        this.rolledUpNeedsAttentionWorkItems?.count
      );
    },
    onTrackText() {
      return sprintf(
        n__(
          'WorkItem|%{boldStart}%{count}%{boldEnd} item on track',
          'WorkItem|%{boldStart}%{count}%{boldEnd} items on track',
          this.rolledUpOnTrackWorkItems.count,
        ),
        { count: this.rolledUpOnTrackWorkItems.count },
      );
    },
    needsAttentionText() {
      return sprintf(
        n__(
          'WorkItem|%{boldStart}%{count}%{boldEnd} item needs attention',
          'WorkItem|%{boldStart}%{count}%{boldEnd} items need attention',
          this.rolledUpNeedsAttentionWorkItems.count,
        ),
        { count: this.rolledUpNeedsAttentionWorkItems.count },
      );
    },
    atRiskText() {
      return sprintf(
        n__(
          'WorkItem|%{boldStart}%{count}%{boldEnd} item at risk',
          'WorkItem|%{boldStart}%{count}%{boldEnd} items at risk',
          this.rolledUpAtRiskWorkItems.count,
        ),
        { count: this.rolledUpAtRiskWorkItems.count },
      );
    },
  },
};
</script>

<template>
  <div
    v-if="showRolledUpHealthStatus"
    class="gl-ml-3 gl-cursor-default"
    data-testid="rolled-up-health-status-wrapper"
  >
    <button
      ref="healthStatusRollUp"
      class="gl-flex gl-gap-3 gl-border-0 gl-bg-transparent gl-text-sm gl-text-subtle"
      type="button"
      :aria-label="s__('WorkItem|Health status')"
    >
      <span class="gl-inline-flex gl-gap-1" data-testid="on-track-count">
        <gl-icon name="status-health" class="gl-mr-1 gl-text-success" />
        {{ rolledUpOnTrackWorkItems.count }}
      </span>
      <span class="gl-inline-flex gl-gap-1" data-testid="needs-attention-count">
        <gl-icon name="warning" class="gl-mr-1 gl-text-warning" />
        {{ rolledUpNeedsAttentionWorkItems.count }}
      </span>
      <span class="gl-inline-flex gl-gap-1" data-testid="at-risk-count">
        <gl-icon name="error" class="gl-mr-1 gl-text-danger" />
        {{ rolledUpAtRiskWorkItems.count }}
      </span>
      <span v-if="healthStatusVisible" class="gl-gray-50 gl-border-r gl-bg-subtle"></span>
    </button>

    <gl-popover :target="() => $refs.healthStatusRollUp">
      <template #title>
        {{ s__('WorkItem|Health status') }}
      </template>
      <div class="gl-mb-2" data-testid="on-track-info">
        <gl-icon name="status-health" class="gl-mr-2 gl-text-success" />
        <gl-sprintf :message="onTrackText">
          <template #bold="{ content }">
            <span class="gl-font-bold">{{ content }}</span>
          </template>
        </gl-sprintf>
      </div>
      <div class="gl-mb-2" data-testid="needs-attention-info">
        <gl-icon name="warning" class="gl-mr-2 gl-text-warning" />
        <gl-sprintf :message="needsAttentionText">
          <template #bold="{ content }">
            <span class="gl-font-bold">{{ content }}</span>
          </template>
        </gl-sprintf>
      </div>
      <div data-testid="at-risk-info">
        <gl-icon name="error" class="gl-mr-2 gl-text-danger" />
        <gl-sprintf :message="atRiskText">
          <template #bold="{ content }">
            <span class="gl-font-bold">{{ content }}</span>
          </template>
        </gl-sprintf>
      </div>
    </gl-popover>
  </div>
</template>
