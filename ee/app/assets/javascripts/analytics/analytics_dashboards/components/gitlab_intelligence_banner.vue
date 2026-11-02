<script>
import { GlBadge, GlButton, GlIcon, GlLink } from '@gitlab/ui';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'GitlabIntelligenceBanner',
  components: {
    GlBadge,
    GlButton,
    GlIcon,
    GlLink,
  },
  props: {
    exploreDashboardsPath: {
      type: String,
      required: true,
    },
  },
  // TODO: repoint once the Explore docs land, tracked in
  // https://gitlab.com/gitlab-org/gitlab/-/work_items/589513
  helpPageUrl: helpPagePath('user/analytics/analytics_dashboards'),
  features: [
    {
      icon: 'organization',
      title: s__('Analytics|Organization-wide view'),
      description: s__(
        'Analytics|View activity across groups and projects in one place, instead of multiple dashboards.',
      ),
    },
    {
      icon: 'tanuki-ai',
      title: s__('Analytics|Insights with GitLab Duo'),
      description: s__(
        'Analytics|Ask what trends and metrics mean, and get answers grounded in the data on the page.',
      ),
    },
    {
      icon: 'dashboard',
      title: s__('Analytics|Custom dashboards'),
      comingSoon: true,
      description: s__(
        'Analytics|Start from a template or compose panels yourself, and share dashboards with your groups.',
      ),
    },
  ],
};
</script>

<template>
  <!-- brand-charcoal and neutral-0 are constant tokens, so the card stays dark in both color modes -->
  <section
    class="gradient-hero gl-border gl-rounded-lg gl-border-alpha-light-24 gl-bg-brand-charcoal gl-px-7 gl-py-9 gl-text-center gl-@container"
    data-testid="gitlab-intelligence-banner"
  >
    <div class="gl-mb-4 gl-flex gl-items-center gl-justify-center gl-gap-3">
      <gl-icon name="tanuki-ai" :size="32" class="gl-text-neutral-0" />
      <span class="gl-text-sm gl-font-bold gl-text-neutral-0">
        {{ s__('Analytics|Introducing GitLab Intelligence') }}
      </span>
      <gl-badge variant="info">{{ __('New') }}</gl-badge>
    </div>

    <h2 class="gl-mb-3 gl-mt-0 gl-text-800 gl-text-neutral-0">
      {{ s__('Analytics|See everything. Ask anything.') }}
    </h2>
    <p class="gl-mx-auto gl-mb-0 gl-max-w-80 gl-text-lg gl-text-neutral-100">
      {{
        s__(
          'Analytics|Keep an overview of activity across your entire organization in one place, and get analytical insights from GitLab Duo — without building a dashboard first.',
        )
      }}
      <gl-link
        variant="unstyled"
        :href="$options.helpPageUrl"
        class="gl-text-neutral-0 gl-underline focus-visible:gl-focus"
      >
        {{ s__('Analytics|Learn more') }}</gl-link
      >
    </p>

    <div class="gl-mt-5 gl-flex gl-justify-center">
      <gl-button variant="confirm" class="gradient-hero-cta" :href="exploreDashboardsPath">
        {{ s__('Analytics|Open GitLab Intelligence') }}
      </gl-button>
    </div>

    <ul
      class="gl-border-t gl-mb-0 gl-mt-7 gl-grid gl-list-none gl-grid-cols-1 gl-gap-6 gl-border-alpha-light-24 gl-pl-0 gl-pt-6 gl-text-left @md:gl-grid-cols-3"
    >
      <li v-for="feature in $options.features" :key="feature.icon">
        <gl-icon :name="feature.icon" class="gl-mb-3 gl-text-neutral-100" />
        <div
          class="gl-mb-1 gl-flex gl-flex-wrap gl-content-start gl-items-center gl-gap-x-3 gl-gap-y-1 @md:gl-min-h-6"
        >
          <h3 class="gl-m-0 gl-text-base gl-text-neutral-0">
            {{ feature.title }}
          </h3>
          <gl-badge
            v-if="feature.comingSoon"
            variant="neutral"
            icon="clock"
            data-testid="coming-soon-badge"
          >
            {{ s__('Analytics|Coming soon') }}
          </gl-badge>
        </div>
        <p class="gl-mb-0 gl-text-sm gl-text-neutral-100">
          {{ feature.description }}
        </p>
      </li>
    </ul>
  </section>
</template>
