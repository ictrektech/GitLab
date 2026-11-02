<script>
import { GlCard, GlLink, GlLoadingIcon, GlAlert } from '@gitlab/ui';
import { __ } from '~/locale';

export default {
  name: 'DashboardListCard',
  components: {
    GlCard,
    GlLink,
    GlLoadingIcon,
    GlAlert,
  },
  props: {
    title: {
      type: String,
      required: true,
    },
    viewAllText: {
      type: String,
      required: false,
      default: '',
    },
    viewAllHref: {
      type: String,
      required: false,
      default: null,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    errorText: {
      type: String,
      required: false,
      default: '',
    },
    isEmpty: {
      type: Boolean,
      required: false,
      default: false,
    },
    emptyText: {
      type: String,
      required: false,
      default: '',
    },
    // Set by cards that cannot honour the dashboard date range, to state the
    // window they do use.
    footnote: {
      type: String,
      required: false,
      default: '',
    },
    // Card name sent as the label of the card link click event. Leave empty to
    // keep the view-all link untracked.
    trackingLabel: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    viewAllTrackingAttrs() {
      if (!this.trackingLabel) return {};

      return {
        'data-event-tracking': 'click_card_link_on_ai_governance_dashboard',
        'data-event-label': this.trackingLabel,
        'data-event-property': 'view_all',
      };
    },
  },
  i18n: {
    viewAllShort: __('View all'),
  },
};
</script>

<template>
  <gl-card body-class="gl-p-0">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
        <div class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <h2 class="gl-m-0 gl-text-base gl-font-bold">{{ title }}</h2>
          <slot name="title-badge"></slot>
        </div>
        <gl-link
          v-if="viewAllHref"
          v-bind="viewAllTrackingAttrs"
          :href="viewAllHref"
          :aria-label="viewAllText"
          class="gl-shrink-0"
          data-testid="view-all-link"
        >
          {{ $options.i18n.viewAllShort }}
        </gl-link>
      </div>
    </template>

    <gl-loading-icon v-if="loading" size="md" class="gl-my-6" />
    <gl-alert v-else-if="errorText" variant="danger" :dismissible="false" class="gl-m-3">
      {{ errorText }}
    </gl-alert>
    <div v-else-if="isEmpty" class="gl-p-5 gl-text-center gl-text-subtle" data-testid="empty-state">
      {{ emptyText }}
    </div>
    <ul v-else class="gl-m-0 gl-list-none gl-p-0">
      <slot></slot>
    </ul>

    <template v-if="footnote" #footer>
      <span class="gl-text-sm gl-text-subtle" data-testid="card-footnote">{{ footnote }}</span>
    </template>
  </gl-card>
</template>
