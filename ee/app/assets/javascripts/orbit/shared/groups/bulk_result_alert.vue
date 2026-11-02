<script>
import { defineComponent } from 'vue';
import { GlAlert } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import {
  ACTION_EXCLUDE,
  ACTION_INCLUDE,
  ACTION_TURN_OFF,
  ACTION_TURN_ON,
  LISTED_FAILURES_LIMIT,
} from './constants';

const SUCCESS_TITLES = {
  [ACTION_TURN_ON]: (count) =>
    n__('Orbit|GitLab Orbit is on for %d group', 'Orbit|GitLab Orbit is on for %d groups', count),
  [ACTION_TURN_OFF]: (count) =>
    n__('Orbit|GitLab Orbit is off for %d group', 'Orbit|GitLab Orbit is off for %d groups', count),
  [ACTION_EXCLUDE]: (count) =>
    n__(
      'Orbit|%d group is excluded from automatic indexing',
      'Orbit|%d groups are excluded from automatic indexing',
      count,
    ),
  [ACTION_INCLUDE]: (count) =>
    n__('Orbit|%d group is no longer excluded', 'Orbit|%d groups are no longer excluded', count),
};

export default defineComponent({
  name: 'OrbitBulkResultAlert',
  components: {
    GlAlert,
  },
  props: {
    result: {
      type: Object,
      required: true,
    },
    canRetry: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['dismiss', 'retry'],
  computed: {
    hasFailures() {
      return this.result.failed.length > 0;
    },
    title() {
      if (!this.hasFailures) return SUCCESS_TITLES[this.result.action](this.result.total);

      return sprintf(
        n__(
          'Orbit|%{failed} of %{total} groups was not updated',
          'Orbit|%{failed} of %{total} groups were not updated',
          this.result.failed.length,
        ),
        { failed: this.result.failed.length, total: this.result.total },
      );
    },
    listedFailures() {
      return this.result.failed.slice(0, LISTED_FAILURES_LIMIT);
    },
    unlistedFailuresText() {
      const count = this.result.failed.length - this.listedFailures.length;
      return count > 0 ? n__('Orbit|And %d more group', 'Orbit|And %d more groups', count) : '';
    },
    retryText() {
      return this.hasFailures && this.canRetry ? s__('Orbit|Try again') : '';
    },
    isTurnOnSuccess() {
      return !this.hasFailures && this.result.action === ACTION_TURN_ON;
    },
  },
});
</script>

<template>
  <gl-alert
    :variant="hasFailures ? 'danger' : 'info'"
    :title="title"
    :primary-button-text="retryText"
    data-testid="orbit-bulk-result"
    @dismiss="$emit('dismiss')"
    @primary-action="$emit('retry')"
  >
    <ul v-if="hasFailures" class="gl-mb-0 gl-pl-5">
      <li v-for="failure in listedFailures" :key="failure.fullPath">
        <strong>{{ failure.fullPath }}</strong
        >: {{ failure.message }}
      </li>
      <li v-if="unlistedFailuresText" data-testid="unlisted-failures">
        {{ unlistedFailuresText }}
      </li>
    </ul>
    <template v-else-if="isTurnOnSuccess">
      {{
        s__(
          'Orbit|Indexing starts in a few minutes and can take minutes to hours. You can leave this page and check back later.',
        )
      }}
    </template>
  </gl-alert>
</template>
