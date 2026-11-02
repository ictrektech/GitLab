<script>
import { GlButton, GlModal } from '@gitlab/ui';
import GITLAB_LOGO_SVG_URL from '@gitlab/svgs/dist/illustrations/gitlab_logo.svg?url';
import { __, s__ } from '~/locale';
import { PROMO_URL } from '~/constants';
import { REQUEST_STATE } from 'ee/painted_door_request/utils';
import { getTrialActiveFeatures } from 'ee/vue_shared/subscription/components/constants';
import FreeVsPremiumComparisonTable from 'ee/vue_shared/subscription/components/free_vs_premium_comparison_table.vue';

const SHARED_ROW_IDS = [
  'epics',
  'repositoryPullMirroring',
  'mergeRequestApprovals',
  'mergeTrains',
  'escalationPolicies',
];

const ROWS = [
  {
    id: 'sourceCodeManagement',
    title: s__('ExplorePremium|Source Code Management & CI/CD'),
    freeIncluded: true,
  },
  {
    id: 'duoAgentPlatform',
    title: s__('ExplorePremium|GitLab Duo Agent Platform'),
    freeIncluded: false,
  },
  ...SHARED_ROW_IDS.map((id) => ({
    id,
    title: getTrialActiveFeatures.find((feature) => feature.id === id).title,
    freeIncluded: false,
  })),
];

export default {
  name: 'ExplorePremiumModal',
  components: {
    GlButton,
    GlModal,
    FreeVsPremiumComparisonTable,
  },
  props: {
    visible: {
      type: Boolean,
      required: false,
      default: false,
    },
    state: {
      type: String,
      required: true,
      validator: (value) => Object.values(REQUEST_STATE).includes(value),
    },
  },
  emits: ['change', 'hide', 'request', 'learn-more-click'],
  i18n: {
    heading: s__('ExplorePremium|Get more from GitLab'),
    bodyRequest: s__(
      'ExplorePremium|Premium adds more control over reviews, planning, and delivery. Request an upgrade to unlock it for your group.',
    ),
    bodyExplore: s__(
      'ExplorePremium|Premium adds more control over reviews, planning, and delivery. Explore what it has to offer for your group.',
    ),
    requestPremiumFeatures: s__('ExplorePremium|Request Premium features'),
    requested: s__('ExplorePremium|Interest recorded'),
    learnMore: __('Learn more'),
    requestedSupportingText: s__(
      "ExplorePremium|Thank you for your interest. Your group Owner isn't notified, so ask them directly to upgrade.",
    ),
  },
  gitlabLogoUrl: GITLAB_LOGO_SVG_URL,
  learnMoreUrl: `${PROMO_URL}/pricing/premium`,
  rows: ROWS,
  computed: {
    isRequested() {
      return this.state === REQUEST_STATE.REQUESTED;
    },
    isPreviouslyRequested() {
      return this.state === REQUEST_STATE.PREVIOUSLY_REQUESTED;
    },
    bodyMessage() {
      return this.isPreviouslyRequested
        ? this.$options.i18n.bodyExplore
        : this.$options.i18n.bodyRequest;
    },
    learnMoreVariant() {
      return this.isPreviouslyRequested ? 'confirm' : 'default';
    },
    supportingText() {
      return this.isRequested ? this.$options.i18n.requestedSupportingText : '';
    },
  },
  methods: {
    // aria-disabled (kept for the confirm styling) doesn't block clicks.
    handleRequestClick() {
      if (this.isRequested) return;

      this.$emit('request');
    },
  },
};
</script>

<template>
  <gl-modal
    modal-id="explore-premium-modal"
    size="sm"
    footer-class="!gl-pt-2"
    data-testid="explore-premium-modal"
    :title="$options.i18n.heading"
    :visible="visible"
    @change="$emit('change', $event)"
    @hide="$emit('hide', $event)"
  >
    <template #modal-header>
      <div class="gl-m-auto">
        <img :alt="__('GitLab logo')" :src="$options.gitlabLogoUrl" class="gl-ml-6 gl-h-9 gl-w-9" />
      </div>
    </template>

    <div class="gl-text-center">
      <div class="gl-heading-1-fixed">{{ $options.i18n.heading }}</div>
      <p class="gl-mb-0">{{ bodyMessage }}</p>
    </div>

    <free-vs-premium-comparison-table :rows="$options.rows" />

    <template #modal-footer>
      <div class="!gl-m-0 gl-flex gl-w-full gl-flex-col gl-px-3">
        <div class="gl-flex gl-justify-end gl-gap-3">
          <gl-button
            :variant="learnMoreVariant"
            :href="$options.learnMoreUrl"
            target="_blank"
            data-testid="explore-premium-learn-more-button"
            @click="$emit('learn-more-click')"
          >
            {{ $options.i18n.learnMore }}
          </gl-button>
          <gl-button
            v-if="!isPreviouslyRequested"
            class="!gl-m-0"
            variant="confirm"
            :icon="isRequested ? 'check' : undefined"
            :aria-disabled="isRequested ? 'true' : undefined"
            data-testid="explore-premium-request-button"
            @click="handleRequestClick"
          >
            {{ isRequested ? $options.i18n.requested : $options.i18n.requestPremiumFeatures }}
          </gl-button>
        </div>
        <div
          aria-live="polite"
          class="gl-w-full gl-text-left gl-text-sm gl-leading-20 gl-text-subtle"
          :class="{ 'gl-mt-3': supportingText }"
          data-testid="explore-premium-supporting-text"
        >
          {{ supportingText }}
        </div>
      </div>
    </template>
  </gl-modal>
</template>
