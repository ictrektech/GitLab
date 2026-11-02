<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import { InternalEvents } from '~/tracking';

export default {
  name: 'ScanCoverageRecommendationAlert',
  components: {
    GlAlert,
    GlButton,
    UserGroupCalloutDismisser,
  },
  mixins: [InternalEvents.mixin()],
  inject: ['groupId', 'scanCoverageBanner'],
  computed: {
    bannerType() {
      return this.scanCoverageBanner?.bannerType;
    },
  },
  mounted() {
    // UserGroupCalloutDismisser only exposes shouldShowCallout via its scoped slot, so we
    // read it straight off the child instance: under skip-query it resolves synchronously,
    // and is already settled by the time this mounted() hook runs (children mount first).
    if (this.$refs.dismisser?.shouldShowCallout) {
      this.trackEvent('view_scan_coverage_recommendation_banner', { label: this.bannerType });
    }
  },
  methods: {
    handleDismiss(dismiss) {
      this.trackEvent('dismiss_scan_coverage_recommendation_banner', { label: this.bannerType });
      dismiss();
    },
  },
};
</script>

<template>
  <user-group-callout-dismisser
    v-if="scanCoverageBanner"
    ref="dismisser"
    feature-name="scan_coverage_recommendation_banner"
    :group-id="groupId"
    skip-query
  >
    <template #default="{ dismiss, shouldShowCallout }">
      <gl-alert
        v-if="shouldShowCallout"
        :variant="scanCoverageBanner.variant"
        :title="scanCoverageBanner.title"
        class="gl-mb-5"
        @dismiss="handleDismiss(dismiss)"
      >
        {{ scanCoverageBanner.message }}
        <template #actions>
          <gl-button
            :href="scanCoverageBanner.ctaUrl"
            variant="confirm"
            data-event-tracking="click_scan_coverage_recommendation_banner_cta"
            :data-event-label="bannerType"
            >{{ scanCoverageBanner.ctaText }}</gl-button
          >
        </template>
      </gl-alert>
    </template>
  </user-group-callout-dismisser>
</template>
