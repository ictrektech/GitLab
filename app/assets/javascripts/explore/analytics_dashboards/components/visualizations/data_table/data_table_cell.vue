<script>
import { defineAsyncComponent } from 'vue';
import { GlIcon, GlLink } from '@gitlab/ui';
import { __ } from '~/locale';
import { isExternal } from '~/lib/utils/url_utility';
import { formatVisualizationValue } from '../utils';

export default {
  name: 'DataTableCell',
  components: {
    GlIcon,
    GlLink,
    AssigneeAvatars: defineAsyncComponent(() => import('./assignee_avatars.vue')),
    CalculateSum: defineAsyncComponent(() => import('./calculate_sum.vue')),
    DiffLineChanges: defineAsyncComponent(() => import('./diff_line_changes.vue')),
    CalculatePercent: defineAsyncComponent(() => import('./calculate_percent.vue')),
    FormatNumber: defineAsyncComponent(() => import('./format_number.vue')),
    FormatText: defineAsyncComponent(() => import('./format_text.vue')),
    FormatTime: defineAsyncComponent(() => import('./format_time.vue')),
    FormatTimeRange: defineAsyncComponent(() => import('./format_time_range.vue')),
    MergeRequestLink: defineAsyncComponent(() => import('./merge_request_link.vue')),
    MilestoneLink: defineAsyncComponent(() => import('./milestone_link.vue')),
    ChangePercentageIndicator: defineAsyncComponent(
      () => import('./change_percentage_indicator.vue'),
    ),
    MetricLabel: defineAsyncComponent(() => import('./metric_label.vue')),
    ProjectAvatar: defineAsyncComponent(() => import('./project_avatar.vue')),
    TrendLine: defineAsyncComponent(() => import('./trend_line.vue')),
    UserLink: defineAsyncComponent(() => import('./user_link.vue')),
  },
  props: {
    value: {
      type: [String, Number, Boolean, Object, Array],
      required: false,
      default: null,
    },
    field: {
      type: Object,
      required: true,
    },
  },
  computed: {
    isLink() {
      return Boolean(this.value?.text && this.value?.href);
    },
    isExternalLink() {
      return isExternal(this.value.href);
    },
  },
  methods: {
    formatVisualizationValue,
  },
  i18n: {
    externalLink: __('external link'),
  },
};
</script>

<template>
  <component :is="field.component" v-if="field.component" v-bind="value" />
  <gl-link v-else-if="isLink" :href="value.href"
    >{{ formatVisualizationValue(value.text) }}
    <gl-icon
      v-if="isExternalLink"
      name="external-link"
      :size="12"
      :aria-label="$options.i18n.externalLink"
      class="gl-ml-1"
    />
  </gl-link>
  <span v-else>{{ formatVisualizationValue(value) }}</span>
</template>
