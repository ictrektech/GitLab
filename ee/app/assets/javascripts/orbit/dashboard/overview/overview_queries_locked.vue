<script>
import { defineComponent } from 'vue';
import { GlButton } from '@gitlab/ui';
import orbitLogoUrl from 'ee_images/illustrations/orbit/orbit-logo.svg?url';
import { s__ } from '~/locale';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import { ACCESS_STATE, PURCHASE_ONLY_STATES } from 'ee/orbit/access/constants';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';

const CARD = {
  STATUS_UNAVAILABLE: 'status_unavailable',
  START_TRIAL: 'start_trial',
  ADMIN: 'admin',
  MEMBER: 'member',
  MEMBER_TRIAL: 'member_trial',
  MEMBER_PURCHASE: 'member_purchase',
};

const CONTENT = {
  [CARD.STATUS_UNAVAILABLE]: {
    title: s__('Orbit|Trial status is not available right now'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. GitLab Orbit could not check the trial status of this instance. Try again later.',
    ),
  },
  [CARD.START_TRIAL]: {
    title: s__('Orbit|Explore the map with a trial or a purchase'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. Start the trial of this instance to explore the map and run GitLab Orbit queries. All groups share the trial credits.',
    ),
  },
  [CARD.ADMIN]: {
    title: s__('Orbit|Explore the map with a purchase'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. To explore the map and run GitLab Orbit queries, contact sales to buy GitLab Orbit for this instance.',
    ),
  },
  [CARD.MEMBER]: {
    title: s__('Orbit|Explore the map with a trial or a purchase'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. To explore the map and run GitLab Orbit queries, this instance needs a trial or a purchase. Contact sales, or ask your administrator.',
    ),
  },
  [CARD.MEMBER_TRIAL]: {
    title: s__('Orbit|Try GitLab Orbit on this instance'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. Ask your administrator to start the trial of this instance to explore the map and run GitLab Orbit queries.',
    ),
  },
  [CARD.MEMBER_PURCHASE]: {
    title: s__('Orbit|Explore the map with a purchase'),
    text: s__(
      'Orbit|GitLab Orbit indexes your groups and counts their items. To explore the map and run GitLab Orbit queries, this instance needs a purchase. Contact sales, or ask your administrator.',
    ),
  },
};

export default defineComponent({
  name: 'OverviewQueriesLocked',
  components: { ContactSalesButton, GlButton },
  props: {
    accessState: { type: String, required: false, default: null },
    adminPath: { type: String, required: false, default: null },
  },
  computed: {
    card() {
      if (this.accessState === ACCESS_STATE.TRIAL_STATUS_UNAVAILABLE)
        return CARD.STATUS_UNAVAILABLE;
      if (!this.adminPath) {
        if (this.accessState === ACCESS_STATE.TRIAL_ELIGIBLE) return CARD.MEMBER_TRIAL;
        return PURCHASE_ONLY_STATES.includes(this.accessState) ? CARD.MEMBER_PURCHASE : CARD.MEMBER;
      }

      return this.accessState === ACCESS_STATE.TRIAL_ELIGIBLE ? CARD.START_TRIAL : CARD.ADMIN;
    },
    content() {
      return CONTENT[this.card];
    },
    showsStartTrial() {
      return this.card === CARD.START_TRIAL;
    },
    showsTryAgain() {
      return this.card === CARD.STATUS_UNAVAILABLE;
    },
    showsContactSales() {
      return this.card !== CARD.MEMBER_TRIAL;
    },
  },
  methods: {
    tryAgain() {
      refreshCurrentPage();
    },
  },
  orbitLogoUrl,
});
</script>

<template>
  <div
    class="gl-absolute gl-inset-0 gl-z-1 gl-flex gl-items-center gl-justify-center gl-bg-alpha-light-36 gl-p-5 gl-backdrop-blur-md dark:gl-bg-alpha-dark-40"
    data-testid="overview-queries-locked"
  >
    <section
      class="gl-border gl-flex gl-max-w-62 gl-flex-col gl-items-start gl-gap-3 gl-rounded-xl gl-border-default gl-bg-default gl-p-5 gl-shadow-md"
      aria-labelledby="orbit-queries-locked-title"
    >
      <img :src="$options.orbitLogoUrl" :alt="''" width="48" height="48" />
      <h2 id="orbit-queries-locked-title" class="gl-heading-4 gl-mb-0">{{ content.title }}</h2>
      <p class="gl-mb-0 gl-text-subtle" data-testid="overview-queries-locked-text">
        {{ content.text }}
      </p>
      <div class="gl-flex gl-flex-wrap gl-gap-3">
        <gl-button
          v-if="showsStartTrial"
          variant="confirm"
          :href="adminPath"
          data-testid="overview-queries-locked-trial"
        >
          {{ s__('Orbit|Go to GitLab Orbit settings') }}
        </gl-button>
        <gl-button
          v-if="showsTryAgain"
          data-testid="overview-queries-locked-retry"
          @click="tryAgain"
        >
          {{ s__('Orbit|Try again') }}
        </gl-button>
        <contact-sales-button v-if="showsContactSales" glm-content="orbit-overview-queries" />
      </div>
    </section>
  </div>
</template>
