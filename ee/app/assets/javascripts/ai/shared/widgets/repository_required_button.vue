<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import FlowUnavailableButton from './flow_unavailable_button.vue';

export default {
  name: 'RepositoryRequiredButton',
  components: {
    FlowUnavailableButton,
    GlLink,
    GlSprintf,
  },
  mixins: [glSlotsMixin],
  props: {
    projectWebPath: {
      type: String,
      required: true,
    },
    size: {
      type: String,
      default: 'small',
      required: false,
    },
    variant: {
      type: String,
      default: 'default',
      required: false,
    },
    category: {
      type: String,
      default: 'primary',
      required: false,
    },
  },
};
</script>
<template>
  <flow-unavailable-button :category="category" :size="size" :variant="variant">
    <template #message>
      <gl-sprintf
        :message="
          s__(
            `DuoAgentPlatform|This project doesn't have a repository yet. %{linkStart}Add a repository%{linkEnd} to get started with flows.`,
          )
        "
      >
        <template #link="{ content }">
          <gl-link :href="projectWebPath">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </template>
    <template v-if="glSlots().default" #default><slot></slot></template>
  </flow-unavailable-button>
</template>
