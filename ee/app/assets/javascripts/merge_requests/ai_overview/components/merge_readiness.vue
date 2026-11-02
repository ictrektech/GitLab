<script>
import { s__, sprintf } from '~/locale';
import { NON_OPEN_STATE } from '../constants';
import { buildRows, getVerdict, isViewerBlockingReviewer } from '../utils';
import ReadinessRow from './readiness_row.vue';

export default {
  name: 'MergeReadiness',
  components: {
    ReadinessRow,
  },
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  computed: {
    rows() {
      return buildRows(this.mergeRequest);
    },
    passingCount() {
      return this.rows.filter((row) => row.passing).length;
    },
    verdict() {
      return getVerdict(this.rows);
    },
    // Everything but an open merge request replaces the panel: the merge gate reports `not_open`
    // as a failing check, which would otherwise read as "not ready to merge" on a merged one.
    nonOpenState() {
      return NON_OPEN_STATE[this.mergeRequest.state] || null;
    },
    checksPassingText() {
      return sprintf(s__('AiOverview|%{passing} of %{total} checks passing'), {
        passing: this.passingCount,
        total: this.rows.length,
      });
    },
    isViewerBlockingReviewer() {
      return !this.nonOpenState && isViewerBlockingReviewer(this.mergeRequest, this.rows);
    },
    heroTitle() {
      if (this.nonOpenState) return this.nonOpenState.title;
      if (this.isViewerBlockingReviewer) return this.$options.i18n.yourReviewBlocks;

      return this.verdict.title;
    },
  },
  i18n: {
    yourReviewBlocks: s__('AiOverview|Your review is the blocker'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-2">
    <div
      class="gl-flex gl-items-center gl-justify-between gl-gap-4 gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-default gl-px-4 gl-py-3"
    >
      <div class="gl-min-w-0">
        <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ heroTitle }}</h3>
        <p v-if="nonOpenState" class="gl-mb-0 gl-mt-1 gl-text-subtle">
          {{ nonOpenState.summary }}
        </p>
      </div>
      <span v-if="!nonOpenState" class="gl-shrink-0 gl-text-subtle">{{ checksPassingText }}</span>
    </div>

    <ul v-if="!nonOpenState" class="gl-m-0 gl-list-none gl-p-0">
      <readiness-row v-for="row in rows" :key="row.key" :row="row" />
    </ul>
  </div>
</template>
