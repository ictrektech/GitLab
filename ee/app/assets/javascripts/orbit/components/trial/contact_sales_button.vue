<script>
import { GlButton } from '@gitlab/ui';
import HandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/components/hand_raise_lead_button.vue';
import { ORBIT_SALES_URL } from 'ee/orbit/constants';

// The hand-raise lead form exists only on GitLab.com; other instances link to the sales page.
export default {
  name: 'OrbitContactSalesButton',
  components: { GlButton, HandRaiseLeadButton },
  inject: ['orbitPlatform'],
  props: {
    glmContent: { type: String, required: true },
    size: { type: String, required: false, default: 'medium' },
    namespaceId: { type: Number, required: false, default: null },
  },
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    buttonAttributes() {
      return { category: 'secondary', size: this.size };
    },
  },
  tracking: { action: 'click_button', label: 'orbit_contact_sales' },
  salesUrl: ORBIT_SALES_URL,
};
</script>

<template>
  <hand-raise-lead-button
    v-if="saas"
    :glm-content="glmContent"
    :button-text="s__('Orbit|Contact sales')"
    :button-attributes="buttonAttributes"
    :cta-tracking="$options.tracking"
    :namespace-id="namespaceId"
    product-interaction="Requested Contact-Orbit"
    data-testid="orbit-contact-sales-button"
  />
  <gl-button
    v-else
    v-bind="buttonAttributes"
    :href="$options.salesUrl"
    target="_blank"
    data-testid="orbit-contact-sales-button"
  >
    {{ s__('Orbit|Contact sales') }}
  </gl-button>
</template>
