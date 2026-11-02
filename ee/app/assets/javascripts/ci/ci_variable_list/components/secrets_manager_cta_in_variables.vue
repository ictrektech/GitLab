<script>
import {
  GlBadge,
  GlButton,
  GlIcon,
  GlLink,
  GlModal,
  GlModalDirective,
  GlSprintf,
} from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { __ } from '~/locale';
import { InternalEvents } from '~/tracking';
import {
  I18N_REQUEST_TEXT,
  SECRETS_MANAGER_CTA_CLICK_EVENT,
  SECRETS_MANAGER_CTA_LABEL_LEARN_MORE,
  SECRETS_MANAGER_CTA_VIEW_EVENT,
  SECRETS_MANAGER_REQUEST_MODAL_ID,
  VARIANT_INFO,
  VARIANT_REQUEST,
  VARIANT_TRY,
  VARIANT_VIEW,
  VARIANTS,
} from '../constants';

export default {
  name: 'SecretsManagerCtaInVariables',
  components: { GlBadge, GlButton, GlIcon, GlLink, GlModal, GlSprintf },
  directives: { GlModal: GlModalDirective },
  mixins: [InternalEvents.mixin()],
  inject: {
    secretsManagerCtaInVariables: { default: null },
  },
  props: {
    entity: {
      type: String,
      required: true,
    },
    // The drawer keeps this card mounted and toggles it as the visibility changes, so a user
    // switching between options does not count as a new view.
    visible: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['modal-toggle'],
  data() {
    return {
      hasTrackedView: false,
    };
  },
  computed: {
    cta() {
      return this.secretsManagerCtaInVariables ?? {};
    },
    variantKey() {
      if (this.cta.secretsManagerAvailable) {
        return this.cta.secretsPath ? VARIANT_VIEW : VARIANT_INFO;
      }

      return this.cta.canStartTrial ? VARIANT_TRY : VARIANT_REQUEST;
    },
    variant() {
      return VARIANTS[this.variantKey];
    },
    needsRequest() {
      return this.variantKey === VARIANT_REQUEST;
    },
    actionPath() {
      if (this.variantKey === VARIANT_VIEW) return this.cta.secretsPath;

      return this.variantKey === VARIANT_TRY ? this.cta.startTrialPath : undefined;
    },
  },
  watch: {
    visible: {
      immediate: true,
      handler(isVisible) {
        if (isVisible) this.trackView();
      },
    },
  },
  methods: {
    // Once per drawer session, the first time the card is shown.
    trackView() {
      if (this.hasTrackedView) return;

      this.hasTrackedView = true;
      this.trackEvent(SECRETS_MANAGER_CTA_VIEW_EVENT, {
        label: this.variant.actionLabel,
        property: this.entity,
      });
    },
    trackActionClick() {
      this.trackEvent(SECRETS_MANAGER_CTA_CLICK_EVENT, {
        label: this.variant.actionLabel,
        property: this.entity,
      });
    },
    trackLearnMoreClick() {
      this.trackEvent(SECRETS_MANAGER_CTA_CLICK_EVENT, {
        label: SECRETS_MANAGER_CTA_LABEL_LEARN_MORE,
        property: this.entity,
      });
    },
  },
  learnMorePath: helpPagePath('ci/secrets/secrets_manager/_index'),
  requestModalId: SECRETS_MANAGER_REQUEST_MODAL_ID,
  requestModalTitle: I18N_REQUEST_TEXT,
  requestModalCancel: { text: __('Close') },
};
</script>

<template>
  <div
    v-show="visible"
    class="gl-border gl-mx-5 gl-mb-5 gl-rounded-lg gl-border-default gl-bg-subtle gl-p-4"
    data-testid="secrets-manager-cta"
  >
    <header class="gl-mb-3 gl-flex gl-items-center gl-gap-3">
      <gl-icon
        :name="variant.icon"
        :class="{ 'gl-text-purple-600': !variant.showNewBadge }"
        class="gl-shrink-0"
      />
      <h3 class="gl-heading-5 gl-m-0 gl-min-w-0" data-testid="secrets-manager-cta-title">
        {{ variant.title }}
      </h3>
      <gl-badge v-if="variant.showNewBadge" variant="info">{{ __('New') }}</gl-badge>
    </header>
    <p class="gl-mb-0 gl-leading-20 gl-text-subtle" data-testid="secrets-manager-cta-body">
      <gl-sprintf :message="variant.body">
        <template #link="{ content }">
          <gl-link :href="$options.learnMorePath" target="_blank" @click="trackLearnMoreClick">{{
            content
          }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
    <gl-button
      v-if="variant.actionText"
      v-gl-modal="needsRequest ? $options.requestModalId : undefined"
      :href="actionPath"
      target="_blank"
      category="secondary"
      class="gl-mt-4"
      data-testid="secrets-manager-cta-button"
      @click="trackActionClick"
    >
      {{ variant.actionText }}
    </gl-button>
    <gl-modal
      v-if="needsRequest"
      :modal-id="$options.requestModalId"
      :title="$options.requestModalTitle"
      :action-cancel="$options.requestModalCancel"
      data-testid="secrets-manager-request-modal"
      @show="$emit('modal-toggle', true)"
      @hidden="$emit('modal-toggle', false)"
    >
      {{
        s__(
          'SecretsManager|To use GitLab Secrets Manager, request it from your group owner or instance administrator.',
        )
      }}
    </gl-modal>
  </div>
</template>
