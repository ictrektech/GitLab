<script>
import { defineComponent } from 'vue';
import { GlBadge, GlButton, GlIcon, GlModal } from '@gitlab/ui';
import { __, s__, sprintf } from '~/locale';
import { ACCESS_REASON, ACCESS_STATE } from '../../access/constants';
import { INSTANCE_TEXT } from '../../access/instance_text';
import ContactSalesButton from '../../components/trial/contact_sales_button.vue';
import { daysText, freeCreditsText, trialDateText } from '../../utils/trial_offer_text';

const CARD = {
  BETA: 'beta',
  PURCHASED: 'purchased',
  TRIAL: 'trial',
  TRIAL_ACTIVE: 'trial_active',
  TRIAL_ENDED: 'trial_ended',
  CREDITS_USED_UP: 'credits_used_up',
  NOT_ELIGIBLE: 'not_eligible',
  NOT_AVAILABLE: 'not_available',
};

const SALES_CARDS = [
  CARD.TRIAL_ACTIVE,
  CARD.TRIAL_ENDED,
  CARD.CREDITS_USED_UP,
  CARD.NOT_ELIGIBLE,
  CARD.NOT_AVAILABLE,
];

export default defineComponent({
  name: 'AdminInstanceAccessCard',
  components: { ContactSalesButton, GlBadge, GlButton, GlIcon, GlModal },
  props: {
    access: { type: Object, required: true },
    starting: { type: Boolean, required: true },
    confirmVisible: { type: Boolean, required: true },
  },
  emits: ['show-confirm', 'hide-confirm', 'start-trial'],
  computed: {
    card() {
      switch (this.access.state) {
        case ACCESS_STATE.LICENSED:
          return this.access.reason === ACCESS_REASON.PROMO_ADD_ON ? CARD.PURCHASED : CARD.BETA;
        case ACCESS_STATE.TRIAL_ELIGIBLE:
          return CARD.TRIAL;
        case ACCESS_STATE.TRIAL_ACTIVE:
          return CARD.TRIAL_ACTIVE;
        // A trial can use up its credits before its end date, so that date is not when it ended.
        case ACCESS_STATE.TRIAL_ENDED:
          return this.access.reason === ACCESS_REASON.CREDITS_EXHAUSTED
            ? CARD.CREDITS_USED_UP
            : CARD.TRIAL_ENDED;
        case ACCESS_STATE.TRIAL_NOT_ELIGIBLE:
          return CARD.NOT_ELIGIBLE;
        default:
          return CARD.NOT_AVAILABLE;
      }
    },
    offer() {
      return this.access.trial?.offer ?? null;
    },
    trialDate() {
      const expiresOn = this.access.trial?.expiresOn;
      return expiresOn ? trialDateText(expiresOn) : null;
    },
    content() {
      switch (this.card) {
        case CARD.BETA:
          return {
            title: s__('Orbit|GitLab Orbit beta'),
            badge: { text: s__('Orbit|Beta'), variant: 'neutral' },
            text: s__(
              'Orbit|This instance is in the GitLab Orbit beta. You and the Owners of top-level groups can turn on GitLab Orbit.',
            ),
          };
        case CARD.PURCHASED:
          return {
            title: s__('Orbit|GitLab Orbit is on your subscription'),
            badge: { text: s__('Orbit|Purchased'), variant: 'success' },
            text: s__('Orbit|You and the Owners of top-level groups can turn on GitLab Orbit.'),
          };
        case CARD.TRIAL:
          return {
            title: s__('Orbit|Try GitLab Orbit on this instance'),
            badge: { text: s__('Orbit|Trial'), variant: 'info' },
            text: this.trialOfferText,
          };
        case CARD.TRIAL_ACTIVE:
          return {
            title: s__('Orbit|Trial for this instance'),
            badge: { text: s__('Orbit|Trial active'), variant: 'info' },
            text: this.trialActiveText,
          };
        case CARD.TRIAL_ENDED:
          return {
            title: INSTANCE_TEXT.TRIAL_ENDED_TITLE,
            badge: { text: s__('Orbit|Trial ended'), variant: 'warning' },
            text: this.trialEndedText,
          };
        case CARD.CREDITS_USED_UP:
          return {
            title: INSTANCE_TEXT.TRIAL_ENDED_TITLE,
            badge: { text: s__('Orbit|Credits used up'), variant: 'warning' },
            text: s__(
              'Orbit|The trial credits are used up. GitLab Orbit keeps indexing your groups. Contact sales to buy GitLab Orbit and run queries again.',
            ),
          };
        case CARD.NOT_ELIGIBLE:
          return {
            title: s__('Orbit|Buy GitLab Orbit to run queries on this instance'),
            badge: null,
            text: s__(
              'Orbit|You can turn on GitLab Orbit for groups, and GitLab Orbit indexes them. To run GitLab Orbit queries, contact sales to buy GitLab Orbit.',
            ),
          };
        default:
          return {
            title: INSTANCE_TEXT.NOT_AVAILABLE_TITLE,
            badge: null,
            text: s__('Orbit|Contact sales to get GitLab Orbit for this instance.'),
          };
      }
    },
    trialOfferText() {
      if (!this.offer) {
        return s__(
          'Orbit|You can turn on GitLab Orbit for groups now, and GitLab Orbit indexes them. Start a trial to run GitLab Orbit queries. All groups share the trial credits.',
        );
      }

      return sprintf(
        s__(
          'Orbit|You can turn on GitLab Orbit for groups now, and GitLab Orbit indexes them. Start a trial to get %{credits} for GitLab Orbit queries, valid for %{days}. All groups share the credits.',
        ),
        {
          credits: freeCreditsText(this.offer.initialCredits),
          days: daysText(this.offer.durationDays),
        },
      );
    },
    trialActiveText() {
      if (!this.trialDate)
        return s__('Orbit|All groups share the credits for GitLab Orbit queries.');

      return sprintf(
        s__(
          'Orbit|The trial ends on %{date}. All groups share the credits for GitLab Orbit queries.',
        ),
        { date: this.trialDate },
      );
    },
    trialEndedText() {
      if (!this.trialDate) {
        return s__(
          'Orbit|GitLab Orbit keeps indexing your groups, and GitLab Orbit queries are paused. You can still turn on GitLab Orbit for groups. Contact sales to buy GitLab Orbit and run queries again.',
        );
      }

      return sprintf(
        s__(
          'Orbit|The trial ended on %{date}. GitLab Orbit keeps indexing your groups, and GitLab Orbit queries are paused. You can still turn on GitLab Orbit for groups. Contact sales to buy GitLab Orbit and run queries again.',
        ),
        { date: this.trialDate },
      );
    },
    confirmText() {
      if (!this.offer) return s__('Orbit|All groups share the trial credits.');

      return sprintf(
        s__(
          'Orbit|This instance gets %{credits} for GitLab Orbit queries, valid for %{days}. All groups share the credits.',
        ),
        {
          credits: freeCreditsText(this.offer.initialCredits),
          days: daysText(this.offer.durationDays),
        },
      );
    },
    showsStartTrial() {
      return this.card === CARD.TRIAL;
    },
    showsSales() {
      return SALES_CARDS.includes(this.card);
    },
    actionPrimary() {
      return {
        text: s__('Orbit|Start trial'),
        attributes: { variant: 'confirm', loading: this.starting },
      };
    },
    actionCancel() {
      return { text: __('Cancel'), attributes: { disabled: this.starting } };
    },
  },
});
</script>

<template>
  <section
    class="gl-border gl-flex gl-flex-wrap gl-items-start gl-gap-5 gl-rounded-xl gl-border-section gl-bg-section gl-p-5"
    :aria-label="content.title"
    data-testid="orbit-instance-access-card"
  >
    <gl-icon name="orbit" :size="32" class="gl-shrink-0" />
    <div class="gl-flex gl-min-w-0 gl-flex-1 gl-flex-col gl-gap-2">
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <h2 class="gl-heading-4 gl-mb-0" data-testid="orbit-instance-access-title">
          {{ content.title }}
        </h2>
        <gl-badge v-if="content.badge" :variant="content.badge.variant">{{
          content.badge.text
        }}</gl-badge>
      </div>
      <p class="gl-mb-0 gl-text-subtle" data-testid="orbit-instance-access-text">
        {{ content.text }}
      </p>
    </div>
    <gl-button
      v-if="showsStartTrial"
      variant="confirm"
      :loading="starting"
      data-testid="orbit-instance-start-trial"
      @click="$emit('show-confirm')"
    >
      {{ s__('Orbit|Start trial') }}
    </gl-button>
    <contact-sales-button v-else-if="showsSales" glm-content="orbit-admin" />

    <gl-modal
      modal-id="orbit-instance-start-trial-modal"
      :visible="confirmVisible"
      :title="s__('Orbit|Start a GitLab Orbit trial?')"
      :action-primary="actionPrimary"
      :action-cancel="actionCancel"
      @primary.prevent="$emit('start-trial')"
      @hidden="$emit('hide-confirm')"
    >
      <div class="gl-flex gl-flex-col gl-gap-3">
        <p class="gl-mb-0">{{ confirmText }}</p>
        <p class="gl-mb-0">
          {{
            s__(
              'Orbit|After the trial starts, GitLab Orbit queries work for every group that has GitLab Orbit on. When the trial ends or the credits run out, GitLab Orbit keeps indexing your groups. Contact sales to keep running GitLab Orbit queries.',
            )
          }}
        </p>
      </div>
    </gl-modal>
  </section>
</template>
