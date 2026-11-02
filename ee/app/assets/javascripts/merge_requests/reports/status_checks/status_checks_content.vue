<script>
import { __, s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import ReportSection from '~/merge_requests/reports/components/report_section.vue';
import { statusChecksSummary } from 'ee/vue_merge_request_widget/widgets/status_checks/utils';

export default {
  name: 'StatusChecksContent',
  components: {
    ReportSection,
  },
  inject: [
    'isStatusChecksLoading',
    'errorMessage',
    'checks',
    'statusIconName',
    'sections',
    'retryFetch',
  ],
  i18n: {
    loading: s__('StatusCheck|Status checks are being fetched'),
  },
  computed: {
    summary() {
      if (this.errorMessage) return { title: this.errorMessage };

      return statusChecksSummary(this.checks);
    },
    actionButtons() {
      if (!this.errorMessage) return [];

      return [{ text: __('Retry'), onClick: this.retryFetch }];
    },
  },
  helpPopover: {
    options: {
      title: s__('StatusCheck|What is status check?'),
    },
    content: {
      text: s__(
        'StatusCheck|Status checks are API calls to external systems that request the status of an external requirement.',
      ),
      learnMorePath: helpPagePath('user/project/merge_requests/status_checks'),
    },
  },
};
</script>

<template>
  <report-section
    :is-loading="isStatusChecksLoading"
    :loading-text="$options.i18n.loading"
    :summary="summary"
    :status-icon-name="statusIconName"
    :help-popover="$options.helpPopover"
    :action-buttons="actionButtons"
    :sections="sections"
  />
</template>
