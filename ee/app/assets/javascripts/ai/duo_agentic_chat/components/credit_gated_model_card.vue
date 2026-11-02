<script>
import { GlButton, GlCard } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import {
  DUO_PANEL_EVENT_CLICK_GATED_MODEL_LEARN_MORE,
  DUO_PANEL_EVENT_CLICK_GATED_MODEL_PURCHASE,
  DUO_PANEL_EVENT_VIEW_GATED_MODEL_CARD,
} from '../../constants';

export default {
  name: 'CreditGatedModelCard',
  components: {
    GlButton,
    GlCard,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    modelName: {
      type: String,
      required: true,
    },
    modelRef: {
      type: String,
      required: true,
    },
    purchaseCreditsPath: {
      type: String,
      required: false,
      default: '',
    },
    canBuyAddon: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    title() {
      const template = this.canBuyAddon
        ? s__('DuoAgenticChat|Purchase credits to use %{modelName}')
        : s__("DuoAgenticChat|%{modelName} isn't included in your trial");

      return sprintf(template, { modelName: this.modelName });
    },
    description() {
      return this.canBuyAddon
        ? s__(
            "DuoAgenticChat|This model isn't included in your trial. Purchase monthly credits to continue or select another model.",
          )
        : s__(
            'DuoAgenticChat|Select another model, or contact your administrator to purchase monthly credits.',
          );
    },
    showPurchaseCta() {
      return this.canBuyAddon && Boolean(this.purchaseCreditsPath);
    },
    trackedPurchaseCreditsPath() {
      return mergeUrlParams({ ref_source: 'gated_model_chat_card' }, this.purchaseCreditsPath);
    },
  },
  watch: {
    // The card stays mounted when the user switches between gated models.
    // Only buyers see the Purchase button, so only they count as views.
    modelRef: {
      handler() {
        if (this.showPurchaseCta) this.track(DUO_PANEL_EVENT_VIEW_GATED_MODEL_CARD);
      },
      immediate: true,
    },
  },
  methods: {
    track(event) {
      this.trackEvent(event, { label: this.modelRef, property: 'chat' });
    },
    onPurchaseClick() {
      this.track(DUO_PANEL_EVENT_CLICK_GATED_MODEL_PURCHASE);
    },
    onLearnMoreClick() {
      this.track(DUO_PANEL_EVENT_CLICK_GATED_MODEL_LEARN_MORE);
    },
  },
  learnMorePath: helpPagePath('subscriptions/gitlab_credits', { anchor: 'for-the-free-tier' }),
  i18n: {
    purchaseCredits: s__('DuoAgenticChat|Purchase credits'),
    learnMore: s__('DuoAgenticChat|Learn more'),
  },
};
</script>

<template>
  <gl-card data-testid="credit-gated-model-card">
    <template #header>
      <h5 class="gl-heading-5 gl-mb-0" data-testid="credit-gated-model-card-title">
        {{ title }}
      </h5>
    </template>
    <p data-testid="credit-gated-model-card-description">{{ description }}</p>
    <div class="gl-flex gl-gap-3">
      <gl-button
        v-if="showPurchaseCta"
        :href="trackedPurchaseCreditsPath"
        variant="confirm"
        category="primary"
        data-testid="purchase-credits-button"
        @click="onPurchaseClick"
      >
        {{ $options.i18n.purchaseCredits }}
      </gl-button>
      <gl-button
        :href="$options.learnMorePath"
        target="_blank"
        data-testid="learn-more-button"
        @click="onLearnMoreClick"
      >
        {{ $options.i18n.learnMore }}
      </gl-button>
    </div>
  </gl-card>
</template>
