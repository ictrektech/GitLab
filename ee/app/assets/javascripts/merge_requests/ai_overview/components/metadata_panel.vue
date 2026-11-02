<script>
import { GlBadge, GlButton, GlLabel, GlLink, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { isScopedLabel } from '~/lib/utils/common_utils';
import { humanTimeframe, newDate } from '~/lib/utils/datetime_utility';
import metadataQuery from '../queries/mr_ai_overview_metadata.query.graphql';
import labelsSubscription from '../queries/mr_ai_overview_labels.subscription.graphql';
import milestoneSubscription from '../queries/mr_ai_overview_milestone.subscription.graphql';

const MAX_INLINE_LABELS = 3;

export default {
  name: 'MetadataPanel',
  components: {
    GlBadge,
    GlButton,
    GlLabel,
    GlLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['projectPath', 'iid'],
  data() {
    return {
      mergeRequest: null,
      isLabelsExpanded: false,
      labelsListId: uniqueId('ai-overview-labels-'),
    };
  },
  // Its own query keeps labels and milestone out of the main overview query's complexity.
  apollo: {
    mergeRequest: {
      query: metadataQuery,
      variables() {
        return { projectPath: this.projectPath, iid: this.iid };
      },
      update: (data) => data?.project?.mergeRequest,
      error(error) {
        Sentry.captureException(error);
      },
      subscribeToMore: [labelsSubscription, milestoneSubscription].map((document) => ({
        document,
        skip() {
          return !this.mergeRequest?.id;
        },
        variables() {
          return { issuableId: this.mergeRequest?.id };
        },
      })),
    },
  },
  computed: {
    labels() {
      return this.mergeRequest?.labels.nodes ?? [];
    },
    // A few labels fit beside the heading; past that, a count badge and a toggle open them underneath.
    showsLabelsInline() {
      return this.labels.length <= MAX_INLINE_LABELS;
    },
    milestone() {
      return this.mergeRequest?.milestone;
    },
    // Empty when the milestone has no dates, which leaves the link without a tooltip.
    milestoneTimeframe() {
      const { startDate, dueDate } = this.milestone ?? {};

      return humanTimeframe(startDate && newDate(startDate), dueDate && newDate(dueDate));
    },
  },
  methods: {
    isScopedLabel,
  },
};
</script>

<template>
  <section v-if="labels.length || milestone" class="gl-flex gl-flex-col gl-gap-5">
    <div v-if="labels.length" class="gl-flex gl-flex-col gl-gap-3">
      <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
        <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-2">
          <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ __('Labels') }}</h3>
          <gl-badge v-if="!showsLabelsInline" variant="neutral" data-testid="labels-count">
            {{ labels.length }}
          </gl-badge>
        </div>
        <div
          v-if="showsLabelsInline"
          class="gl-flex gl-min-w-0 gl-flex-wrap gl-justify-end gl-gap-2"
          data-testid="labels-inline"
        >
          <gl-label
            v-for="label in labels"
            :key="label.id"
            :background-color="label.color"
            :title="label.title"
            :description="label.description"
            :scoped="isScopedLabel(label)"
          />
        </div>
        <gl-button
          v-else
          category="tertiary"
          size="small"
          :aria-expanded="String(isLabelsExpanded)"
          :aria-controls="labelsListId"
          data-testid="labels-toggle"
          @click="isLabelsExpanded = !isLabelsExpanded"
        >
          {{ isLabelsExpanded ? __('Hide') : __('Show') }}
        </gl-button>
      </div>
      <div
        v-if="!showsLabelsInline"
        v-show="isLabelsExpanded"
        :id="labelsListId"
        class="gl-flex gl-flex-wrap gl-gap-2"
        data-testid="labels-list"
      >
        <gl-label
          v-for="label in labels"
          :key="label.id"
          :background-color="label.color"
          :title="label.title"
          :description="label.description"
          :scoped="isScopedLabel(label)"
        />
      </div>
    </div>
    <div v-if="milestone" class="gl-flex gl-items-center gl-justify-between gl-gap-3">
      <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ __('Milestone') }}</h3>
      <!-- Styled like the milestone in the sidebar, outside the overview. -->
      <gl-link
        v-gl-tooltip="milestoneTimeframe || null"
        :href="milestone.webPath"
        class="!gl-text-inherit hover:!gl-text-link"
        data-testid="milestone-link"
      >
        {{ milestone.title }}
        <span v-if="milestone.expired">{{ __('(expired)') }}</span>
      </gl-link>
    </div>
  </section>
</template>
