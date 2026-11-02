<script>
import { GlCard } from '@gitlab/ui';
import { s__ } from '~/locale';
import DimDisableContainer from '../../dim_disable_container.vue';
import ScopeSection from '../../scope/scope_section.vue';

export default {
  name: 'PolicyScopeCard',
  components: { GlCard, DimDisableContainer, ScopeSection },
  i18n: {
    header: s__('SecurityOrchestration|Policy scope'),
  },
  props: {
    // Not required: transiently undefined while the YAML pane holds unparseable content,
    // during which hasParsingError dims and disables this card anyway.
    policyScope: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    hasParsingError: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['update-property', 'remove-property'],
};
</script>

<template>
  <gl-card>
    <template #header>
      <h4 class="gl-m-0 gl-text-base">{{ $options.i18n.header }}</h4>
    </template>

    <!-- The container's own top margin is meant for a heading above it, which the card
         header already provides. -->
    <dim-disable-container class="!gl-mt-0" :disabled="hasParsingError">
      <template #disabled>
        <div class="gl-rounded-base gl-bg-subtle gl-p-6"></div>
      </template>

      <scope-section
        :policy-scope="policyScope"
        @changed="$emit('update-property', 'policy_scope', $event)"
        @remove="$emit('remove-property', 'policy_scope')"
      />
    </dim-disable-container>
  </gl-card>
</template>
