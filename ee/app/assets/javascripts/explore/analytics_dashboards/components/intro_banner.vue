<script>
import { GlBadge, GlButton, GlIcon, GlLink } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';

export default {
  name: 'IntroBanner',
  components: {
    GlBadge,
    GlButton,
    GlIcon,
    GlLink,
    UserCalloutDismisser,
  },
  helpPageUrl: helpPagePath('user/analytics/analytics_dashboards'),
};
</script>

<template>
  <user-callout-dismisser feature-name="analytics_dashboards_explore_intro_banner">
    <template #default="{ dismiss, shouldShowCallout }">
      <div
        v-if="shouldShowCallout"
        class="gl-flex gl-items-center gl-gap-3 gl-rounded-base gl-bg-feedback-info gl-px-5 gl-py-4"
        data-testid="intro-banner"
      >
        <gl-icon name="tanuki-ai" variant="info" class="gl-shrink-0" />
        <p class="gl-m-0">
          <strong>{{ s__('Analytics|Welcome to GitLab Intelligence') }}</strong>
          <gl-badge variant="info" class="gl-mx-2">{{ __('New') }}</gl-badge>
          {{
            s__('Analytics|Organization-wide analytics with AI-assisted insights from GitLab Duo.')
          }}
          <gl-link :href="$options.helpPageUrl" variant="inline">{{ __('Learn more') }}</gl-link>
        </p>

        <gl-button
          class="gl-ml-auto"
          category="tertiary"
          size="small"
          icon="close"
          :aria-label="__('Dismiss')"
          data-testid="dismiss-button"
          @click="dismiss"
        />
      </div>
    </template>
  </user-callout-dismisser>
</template>
