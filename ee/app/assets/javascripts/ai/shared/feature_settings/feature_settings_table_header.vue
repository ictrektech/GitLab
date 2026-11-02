<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';

export default {
  name: 'FeatureSettingsTableHeader',
  components: {
    GlLink,
    GlSprintf,
  },
  mixins: [glSlotsMixin],
  props: {
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: false,
      default: '',
    },
    link: {
      type: String,
      required: false,
      default: '',
    },
  },
};
</script>
<template>
  <div class="gl-mb-3 gl-flex gl-flex-col gl-gap-3 md:gl-flex-row md:gl-items-start">
    <div class="gl-grow">
      <h2 class="gl-heading-4 gl-my-0">{{ title }}</h2>
      <p v-if="description" class="gl-mb-0 gl-mt-2 gl-text-subtle">
        <gl-sprintf :message="description">
          <template #link="{ content }">
            <gl-link :href="link" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </p>
    </div>
    <div v-if="glSlots().actions" class="gl-shrink-0" data-testid="table-header-actions">
      <slot name="actions"></slot>
    </div>
  </div>
</template>
