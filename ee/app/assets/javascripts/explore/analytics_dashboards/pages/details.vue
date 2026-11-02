<script>
import { defineAsyncComponent } from 'vue';
import { GlButton, GlLink } from '@gitlab/ui';
import ExploreAnalyticsDashboardDetails from '~/explore/analytics_dashboards/pages/details.vue';

export default {
  name: 'ExploreAnalyticsDashboardDetailsEE',
  components: {
    ExploreAnalyticsDashboardDetails,
    GlButton,
    GlLink,
    AnalyzeWithDuoButton: defineAsyncComponent(
      () => import('../components/analyze_with_duo_button.vue'),
    ),
  },
  inject: {
    gitlabCreditsDashboardPath: { default: null },
  },
  computed: {
    showCreditsDashboardLink() {
      return Boolean(this.gitlabCreditsDashboardPath) && this.$route.params.slug === 'dap_impact';
    },
    editPath() {
      return { name: 'dashboard-edit', params: { slug: this.$route.params.slug } };
    },
  },
};
</script>
<template>
  <explore-analytics-dashboard-details>
    <template v-if="showCreditsDashboardLink" #description-append>
      <gl-link
        :href="gitlabCreditsDashboardPath"
        target="_blank"
        show-external-icon
        class="gl-ml-2"
        data-testid="gitlab-credits-dashboard-link"
      >
        {{ s__('AnalyticsDashboards|View GitLab Credits dashboard') }}
      </gl-link>
    </template>
    <template #actions="{ isSystemDashboard }">
      <gl-button
        v-if="!isSystemDashboard"
        icon="pencil"
        :to="editPath"
        data-testid="dashboard-edit-button"
      >
        {{ __('Edit') }}
      </gl-button>
    </template>
    <template #filter-actions="{ filters, panels, duoPrompts, isSystemDashboard }">
      <analyze-with-duo-button
        v-if="isSystemDashboard"
        class="gl-basis-full md:gl-ml-auto md:gl-basis-auto md:gl-self-end"
        :filters="filters"
        :panels="panels"
        :config-prompts="duoPrompts"
      />
    </template>
  </explore-analytics-dashboard-details>
</template>
