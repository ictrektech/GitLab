<script>
import { n__, s__, sprintf } from '~/locale';
import axios from '~/lib/utils/axios_utils';
import { joinPaths } from '~/lib/utils/url_utility';
import { METRICS_ROUTE } from '~/merge_requests/reports/constants';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';
import { metricChangeCount, metricWidgetItems } from './utils';

export default {
  name: 'WidgetMetrics',
  components: {
    MrWidget,
  },
  props: {
    mr: {
      type: Object,
      required: true,
    },
    level: {
      type: Number,
      required: false,
      default: 1,
    },
  },
  emits: ['loaded'],
  i18n: {
    loading: s__('Reports|Metrics reports are loading'),
    error: s__('Reports|Metrics reports failed to load results'),
  },
  data() {
    return {
      collapsedData: {},
    };
  },
  computed: {
    content() {
      return metricWidgetItems(this.collapsedData);
    },
    numberOfChanges() {
      return metricChangeCount(this.collapsedData);
    },
    hasChanges() {
      return this.numberOfChanges > 0;
    },
    statusIcon() {
      return this.hasChanges ? EXTENSION_ICONS.warning : EXTENSION_ICONS.success;
    },
    shouldCollapse() {
      return this.reportPath ? false : this.hasChanges;
    },
    apiMetricsPath() {
      return this.mr.metricsReportsPath;
    },
    reportPath() {
      return this.mr.reportsTabPath ? joinPaths(this.mr.reportsTabPath, METRICS_ROUTE) : '';
    },
    actionButtons() {
      if (!this.reportPath) {
        return [];
      }

      return [
        {
          text: s__('MrReports|View report'),
          href: this.reportPath,
          onClick: (action, event) => {
            // The reports tab is a route in the same app, so navigate without a page reload.
            event?.preventDefault();
            window.history.pushState(null, null, action.href);
            window.dispatchEvent(new PopStateEvent('popstate'));
          },
        },
      ];
    },
    summary() {
      const { hasChanges, numberOfChanges } = this;
      const changesSummary = sprintf(
        s__('Reports|Metrics reports: %{strong_start}%{numberOfChanges}%{strong_end} %{changes}'),
        {
          numberOfChanges,
          changes: n__('change', 'changes', numberOfChanges),
        },
      );
      const noChangesSummary = s__('Reports|Metrics report scanning detected no new changes');
      return hasChanges ? { title: changesSummary } : { title: noChangesSummary };
    },
  },
  methods: {
    onFetchFailed(error) {
      this.$emit('loaded', 0, EXTENSION_ICONS.failed);
      throw error;
    },
    fetchCollapsedData() {
      return axios
        .get(this.apiMetricsPath)
        .then((response) => {
          this.collapsedData = response.data;
          this.$emit('loaded', this.numberOfChanges, this.statusIcon);

          return response;
        })
        .catch(this.onFetchFailed);
    },
  },
};
</script>
<template>
  <mr-widget
    :level="level"
    :action-buttons="actionButtons"
    :error-text="$options.i18n.error"
    :status-icon-name="statusIcon"
    :loading-text="$options.i18n.loading"
    :help-popover="$options.helpPopover"
    :widget-name="$options.name"
    :summary="summary"
    :content="content"
    :is-collapsible="shouldCollapse"
    :expand-button-label="s__('Reports|Expand metrics report details')"
    :collapse-button-label="s__('Reports|Collapse metrics report details')"
    :fetch-collapsed-data="fetchCollapsedData"
  />
</template>
