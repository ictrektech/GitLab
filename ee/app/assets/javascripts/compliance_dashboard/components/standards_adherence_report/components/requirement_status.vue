<script>
import { GlIcon, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';

export default {
  name: 'RequirementStatus',
  components: {
    GlIcon,
    GlLoadingIcon,
    GlSprintf,
  },
  props: {
    pendingCount: {
      type: Number,
      required: true,
    },
    passCount: {
      type: Number,
      required: true,
    },
    failCount: {
      type: Number,
      required: true,
    },
    notApplicableCount: {
      type: Number,
      required: false,
      default: 0,
    },
  },
  computed: {
    totalCount() {
      return this.pendingCount + this.passCount + this.failCount;
    },
    hasPending() {
      return this.pendingCount > 0;
    },
    hasFailed() {
      return this.failCount > 0;
    },
    // Matches backend: a requirement is N/A only when all its controls are N/A
    isNotApplicable() {
      return (
        this.notApplicableCount > 0 && !this.hasFailed && !this.hasPending && this.passCount === 0
      );
    },
    isPassed() {
      return !this.hasPending && !this.hasFailed && !this.isNotApplicable;
    },
    config() {
      if (this.hasFailed) {
        return {
          component: GlIcon,
          props: {
            name: 'status_failed',
          },
          text: 'gl-text-status-danger',
          fill: 'gl-fill-status-danger',
        };
      }

      if (this.hasPending) {
        return {
          component: GlLoadingIcon,
          text: 'gl-text-status-neutral',
          fill: 'gl-fill-status-neutral',
        };
      }

      if (this.isNotApplicable) {
        return {
          component: GlIcon,
          props: {
            name: 'status_skipped',
          },
          text: 'gl-text-status-neutral',
          fill: 'gl-fill-status-neutral',
        };
      }

      if (this.isPassed) {
        return {
          component: GlIcon,
          props: {
            name: 'status_success',
          },
          text: 'gl-text-status-success',
          fill: 'gl-fill-status-success',
        };
      }

      // eslint-disable-next-line @gitlab/require-i18n-strings
      throw new Error('Invalid status');
    },
  },
  i18n: {
    failedControls: s__('ComplianceStandardsAdherence|%{failedCount}/%{totalCount} failed'),
  },
};
</script>

<template>
  <div class="gl-inline-flex gl-flex-row gl-gap-3">
    <component :is="config.component" v-bind="config.props" :class="config.fill" />
    <span :class="config.text">
      <template v-if="hasFailed">
        <gl-sprintf :message="$options.i18n.failedControls">
          <template #failedCount>{{ failCount }}</template>
          <template #totalCount>{{
            n__(
              'ComplianceStandardsAdherence|%d control',
              'ComplianceStandardsAdherence|%d controls',
              totalCount,
            )
          }}</template>
        </gl-sprintf>
      </template>
      <template v-else-if="hasPending">
        {{ s__('ComplianceStandardsAdherence|Pending') }}
      </template>
      <template v-else-if="isNotApplicable">
        {{ s__('ComplianceStandardsAdherence|Not applicable') }}
      </template>
      <template v-else>
        {{ s__('ComplianceStandardsAdherence|Passed') }}
      </template>
    </span>
  </div>
</template>
