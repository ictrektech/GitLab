<script>
import { GlAlert, GlButton, GlLoadingIcon } from '@gitlab/ui';
import ContactSalesButton from './contact_sales_button.vue';

export default {
  name: 'OrbitTrialUnavailableAlert',
  components: { ContactSalesButton, GlAlert, GlButton, GlLoadingIcon },
  props: {
    glmContent: { type: String, required: true },
    namespaceId: { type: Number, required: true },
    reloading: { type: Boolean, required: true },
  },
  emits: ['retry'],
};
</script>

<template>
  <gl-alert
    variant="danger"
    :title="s__('Orbit|Something went wrong')"
    :dismissible="false"
    data-testid="orbit-trial-unavailable-alert"
  >
    {{
      s__(
        'Orbit|Could not load GitLab Orbit trial details for your groups. Try again, or contact sales if this keeps happening.',
      )
    }}
    <gl-loading-icon
      v-if="reloading"
      inline
      size="sm"
      :label="s__('Orbit|Loading groups')"
      data-testid="orbit-trial-unavailable-reloading"
    />
    <template #actions>
      <div class="gl-flex gl-flex-wrap gl-gap-3">
        <gl-button data-testid="orbit-trial-unavailable-retry" @click="$emit('retry')">
          {{ s__('Orbit|Try again') }}
        </gl-button>
        <contact-sales-button :glm-content="glmContent" :namespace-id="namespaceId" />
      </div>
    </template>
  </gl-alert>
</template>
