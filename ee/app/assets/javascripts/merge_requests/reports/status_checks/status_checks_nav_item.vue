<script>
import { STATUS_CHECKS_ROUTE } from '~/merge_requests/reports/constants';
import ReportListItem from '~/merge_requests/reports/components/report_list_item.vue';

export default {
  name: 'StatusChecksNavItem',
  components: {
    ReportListItem,
  },
  inject: ['isStatusChecksLoading', 'statusIconName'],
  routeNames: {
    STATUS_CHECKS_ROUTE,
  },
};
</script>

<template>
  <report-list-item
    :to="$options.routeNames.STATUS_CHECKS_ROUTE"
    :status-icon="statusIconName"
    :is-loading="isStatusChecksLoading"
  >
    {{ s__('MrReports|Status checks') }}
  </report-list-item>
</template>
