<script>
import { InternalEvents } from '~/tracking';
import {
  STATUS_CHECKS_ROUTE,
  VIEW_MERGE_REQUEST_REPORT,
  TRACKING_LABEL_BY_ROUTE,
} from '~/merge_requests/reports/constants';
import StatusChecksProvider from './status_checks_provider.vue';
import StatusChecksContent from './status_checks_content.vue';

export default {
  name: 'StatusChecksPage',
  components: {
    StatusChecksProvider,
    StatusChecksContent,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
  mounted() {
    this.trackEvent(VIEW_MERGE_REQUEST_REPORT, {
      label: TRACKING_LABEL_BY_ROUTE[STATUS_CHECKS_ROUTE],
    });
  },
};
</script>

<template>
  <status-checks-provider :mr="mr">
    <status-checks-content />
  </status-checks-provider>
</template>
