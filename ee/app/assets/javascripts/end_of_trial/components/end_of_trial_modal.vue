<script>
import { GlModal, GlSprintf, GlLink } from '@gitlab/ui';
import GITLAB_LOGO_SVG_URL from '@gitlab/svgs/dist/illustrations/gitlab_logo.svg?url';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import FreeVsPremiumComparisonTable from 'ee/vue_shared/subscription/components/free_vs_premium_comparison_table.vue';
import {
  DUO_CHAT_FEATURE_ID,
  getTrialActiveFeatureHighlights,
} from 'ee/vue_shared/subscription/components/constants';
import { InternalEvents } from '~/tracking';
import { s__, __ } from '~/locale';

const trackingMixin = InternalEvents.mixin();

export default {
  name: 'EndOfTrialModal',
  components: {
    GlModal,
    GlSprintf,
    GlLink,
    UserGroupCalloutDismisser,
    FreeVsPremiumComparisonTable,
  },
  mixins: [trackingMixin],
  props: {
    featureName: {
      type: String,
      required: true,
    },
    groupId: {
      type: Number,
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
    explorePlansPath: {
      type: String,
      required: true,
    },
    upgradeUrl: {
      type: String,
      required: true,
    },
    purchaseCreditsUrl: {
      type: String,
      required: true,
    },
    hasMonthlyCreditCommitment: {
      type: Boolean,
      required: false,
      default: false,
    },
    creditsGeneralizationUi: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  i18n: {
    title: s__('EndOfTrialModal|Your trial has ended'),
    body: s__(
      'EndOfTrialModal|Upgrade %{name} to Premium to maintain access to advanced features and keep your workflow running smoothly.',
    ),
    bodyGeneralized: s__(
      'EndOfTrialModal|Upgrade %{name} to Premium for advanced features, or purchase GitLab Credits to power your usage.',
    ),
    explorePlansPrompt: s__(
      'EndOfTrialModal|Not sure which plan is right for you? %{explorePlansLink}.',
    ),
    explorePlans: s__('EndOfTrialModal|Explore plans'),
  },
  gitlabLogoUrl: GITLAB_LOGO_SVG_URL,
  DUO_CHAT_FEATURE_ID,
  computed: {
    bodyMessage() {
      return this.creditsGeneralizationUi
        ? this.$options.i18n.bodyGeneralized
        : this.$options.i18n.body;
    },
    features() {
      const { features } = getTrialActiveFeatureHighlights({
        usePurchaseCreditsCopy: !this.hasMonthlyCreditCommitment,
        purchaseCreditsUrl: this.purchaseCreditsUrl,
        hasMonthlyCreditCommitment: this.hasMonthlyCreditCommitment,
        creditsGeneralizationUi: this.creditsGeneralizationUi,
      });

      return features;
    },
    rows() {
      return [
        {
          id: 'sourceCodeManagement',
          title: s__('EndOfTrialModal|Source Code Management & CI/CD'),
          freeIncluded: true,
        },
        ...this.features.map((feature) => ({
          ...feature,
          freeIncluded: this.hasMonthlyCreditCommitment && this.isDuoChatFeature(feature),
        })),
      ];
    },
    actionPrimary() {
      return {
        text: __('Upgrade to Premium'),
        attributes: {
          variant: 'confirm',
          href: this.upgradeUrl,
        },
      };
    },
    actionCancel() {
      if (this.hasMonthlyCreditCommitment) {
        return {
          text: s__('EndOfTrialModal|Explore plans'),
          attributes: {
            category: 'secondary',
            variant: 'confirm',
            href: this.explorePlansPath,
          },
        };
      }

      return {
        text: s__('EndOfTrialModal|Purchase GitLab Credits'),
        attributes: {
          category: 'secondary',
          variant: 'confirm',
          href: this.purchaseCreditsUrl,
        },
      };
    },
  },
  methods: {
    isDuoChatFeature(feature) {
      return feature.id === this.$options.DUO_CHAT_FEATURE_ID;
    },
    primary() {
      this.trackEvent('click_upgrade_end_of_trial_modal');
    },
    cancel() {
      if (this.hasMonthlyCreditCommitment) {
        this.trackEvent('click_explore_plans_end_of_trial_modal');
      } else {
        this.trackPurchaseCreditsClick();
      }
    },
    close() {
      this.trackEvent('dismiss_end_of_trial_modal');
    },
    show() {
      this.trackEvent('render_end_of_trial_modal');
    },
    hide(event, dismissFn) {
      if (event.trigger === 'backdrop') {
        this.trackEvent('dismiss_outside_end_of_trial_modal');
      } else if (event.trigger === 'esc') {
        this.trackEvent('dismiss_esc_end_of_trial_modal');
      }

      dismissFn();
    },
    popoverShow(id) {
      this.trackEvent('render_premium_feature_popover_end_of_trial_modal', {
        property: id,
      });
    },
    popoverClick(id) {
      this.trackEvent('click_cta_premium_feature_popover_end_of_trial_modal', {
        property: id,
      });
      if (id === DUO_CHAT_FEATURE_ID && !this.creditsGeneralizationUi) {
        this.trackPurchaseCreditsClick();
      }
    },
    trackPurchaseCreditsClick() {
      this.trackEvent('click_purchase_credits_cta_active_trial', {
        property: 'end_of_trial_modal',
      });
    },
  },
};
</script>

<template>
  <user-group-callout-dismisser :feature-name="featureName" :group-id="groupId" skip-query>
    <template #default="{ dismiss, shouldShowCallout }">
      <gl-modal
        size="sm"
        no-focus-on-show
        modal-id="end-of-trial-modal"
        data-testid="end-of-trial-modal"
        :title="$options.i18n.title"
        :visible="shouldShowCallout"
        :action-primary="actionPrimary"
        :action-cancel="actionCancel"
        @primary="primary"
        @cancel="cancel"
        @close="close"
        @show="show"
        @hide="hide($event, dismiss)"
      >
        <template #modal-header>
          <div class="gl-m-auto">
            <img
              :alt="__('GitLab logo')"
              :src="$options.gitlabLogoUrl"
              class="gl-ml-6 gl-h-9 gl-w-9"
            />
          </div>
        </template>
        <div class="gl-text-center">
          <div class="gl-heading-1-fixed">{{ $options.i18n.title }}</div>

          <gl-sprintf :message="bodyMessage">
            <template #name>
              <span class="gl-font-bold">{{ groupName }}</span>
            </template>
          </gl-sprintf>
          <gl-sprintf
            v-if="!hasMonthlyCreditCommitment"
            :message="$options.i18n.explorePlansPrompt"
          >
            <template #explorePlansLink>
              <gl-link :href="explorePlansPath">{{ $options.i18n.explorePlans }}</gl-link>
            </template>
          </gl-sprintf>
        </div>

        <free-vs-premium-comparison-table
          :rows="rows"
          show-feature-popovers
          @popover-shown="popoverShow"
          @popover-click="popoverClick"
        />
      </gl-modal>
    </template>
  </user-group-callout-dismisser>
</template>
