<script>
import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { INSTANCE_TEXT } from '../access/instance_text';
import ContactSalesButton from '../components/trial/contact_sales_button.vue';
import { PAGE_STATE } from './constants';

export default {
  name: 'OrbitGroupSettingsAlert',
  components: { GlAlert, GlLink, GlSprintf, ContactSalesButton },
  inject: ['orbitPlatform'],
  props: {
    state: {
      type: String,
      required: true,
      validator: (value) => Object.values(PAGE_STATE).includes(value),
    },
    groupName: { type: String, required: true },
    usageQuotasPath: { type: String, required: true },
  },
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    notEligibleTitle() {
      return sprintf(s__('Orbit|Get GitLab Orbit for %{groupName}'), {
        groupName: this.groupName,
      });
    },
    creditsUsedUpTitle() {
      return sprintf(s__('Orbit|%{groupName} has no GitLab Credits left'), {
        groupName: this.groupName,
      });
    },
    unavailableMessage() {
      return this.saas
        ? s__(
            'Orbit|Could not check whether %{groupName} can start a trial. Try again later, or contact sales if this keeps happening.',
          )
        : s__(
            'Orbit|Could not check the trial of this instance. Try again later, or contact sales if this keeps happening.',
          );
    },
    instanceAlert() {
      if (this.state === PAGE_STATE.INSTANCE_NOT_AVAILABLE) {
        return {
          variant: 'info',
          title: INSTANCE_TEXT.NOT_AVAILABLE_TITLE,
          text: INSTANCE_TEXT.NOT_AVAILABLE,
        };
      }
      if (this.state === PAGE_STATE.INSTANCE_TRIAL_ENDED) {
        return {
          variant: 'warning',
          title: INSTANCE_TEXT.TRIAL_ENDED_TITLE,
          text: s__(
            'Orbit|GitLab Orbit queries are paused. GitLab Orbit still indexes this group when it is on. Ask your administrator, or contact sales.',
          ),
        };
      }

      return null;
    },
  },
  orbitDocsPath: helpPagePath('integration/orbit'),
  PAGE_STATE,
};
</script>

<template>
  <gl-alert
    v-if="instanceAlert"
    :variant="instanceAlert.variant"
    :title="instanceAlert.title"
    :dismissible="false"
    data-testid="orbit-instance-alert"
  >
    {{ instanceAlert.text }}
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-instance" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.FREE_PLAN"
    variant="info"
    :title="s__('Orbit|GitLab Orbit is available on Premium and Ultimate')"
    :dismissible="false"
    data-testid="orbit-free-plan-alert"
  >
    <gl-sprintf
      :message="
        s__(
          'Orbit|%{groupName} is on the Free plan. Contact sales to upgrade and get GitLab Orbit for this group. %{linkStart}Learn more about GitLab Orbit%{linkEnd}.',
        )
      "
    >
      <template #groupName>{{ groupName }}</template>
      <template #link="{ content }">
        <gl-link :href="$options.orbitDocsPath">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-free-plan" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.UNLICENSED"
    variant="info"
    :title="s__('Orbit|Get GitLab Orbit for this group')"
    :dismissible="false"
    data-testid="orbit-unlicensed-alert"
  >
    <gl-sprintf
      :message="
        s__(
          'Orbit|Contact sales to get GitLab Orbit for %{groupName}. %{linkStart}Learn more about GitLab Orbit%{linkEnd}.',
        )
      "
    >
      <template #groupName>{{ groupName }}</template>
      <template #link="{ content }">
        <gl-link :href="$options.orbitDocsPath">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-unlicensed" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.CDOT_UNAVAILABLE"
    variant="warning"
    :title="s__('Orbit|Trial status is not available right now')"
    :dismissible="false"
    data-testid="orbit-unavailable-alert"
  >
    <gl-sprintf :message="unavailableMessage">
      <template #groupName>{{ groupName }}</template>
    </gl-sprintf>
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-unavailable" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.NOT_ELIGIBLE"
    variant="info"
    :title="notEligibleTitle"
    :dismissible="false"
    data-testid="orbit-not-eligible-alert"
  >
    {{ s__('Orbit|Contact sales to get GitLab Orbit for this group.') }}
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-not-eligible" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.TRIAL_ENDED"
    variant="warning"
    :title="s__('Orbit|Your GitLab Orbit trial has ended')"
    :dismissible="false"
    data-testid="orbit-trial-ended-alert"
  >
    <gl-sprintf
      :message="
        s__(
          'Orbit|GitLab Orbit is paused for %{groupName}. Contact sales to buy GitLab Credits and keep using GitLab Orbit.',
        )
      "
    >
      <template #groupName>{{ groupName }}</template>
    </gl-sprintf>
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-trial-ended" />
    </div>
  </gl-alert>

  <gl-alert
    v-else-if="state === $options.PAGE_STATE.CREDITS_USED_UP"
    variant="warning"
    :title="creditsUsedUpTitle"
    :dismissible="false"
    data-testid="orbit-no-credits-alert"
  >
    <gl-sprintf
      :message="
        s__(
          'Orbit|GitLab Orbit is paused for this group. Contact sales to buy more GitLab Credits and keep using GitLab Orbit. %{linkStart}View usage quotas%{linkEnd}.',
        )
      "
    >
      <template #link="{ content }">
        <gl-link :href="usageQuotasPath">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
    <div class="gl-mt-3">
      <contact-sales-button glm-content="orbit-credits-used-up" />
    </div>
  </gl-alert>
</template>
