<script>
import { GlButton, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import TanukiAiIcon from '../../shared/widgets/tanuki_ai_icon.vue';

export default {
  name: 'NoBillingForbiddenEmptyState',
  components: {
    GlButton,
    GlSprintf,
    TanukiAiIcon,
  },
  props: {
    isClassicAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['return-to-classic'],
  i18n: {
    headline: s__('DuoAgenticChat|Usage billing not available'),
    description: s__(
      'DuoAgenticChat|Usage billing is not available for this account. To continue using GitLab Duo Agent Platform, contact your administrator.',
    ),
  },
};
</script>

<template>
  <div
    class="gl-flex gl-w-full gl-flex-col gl-items-start gl-gap-4 gl-py-8"
    data-testid="no-billing-forbidden-empty-state"
  >
    <tanuki-ai-icon />
    <h2 class="gl-my-0 gl-text-size-h2">
      {{ $options.i18n.headline }}
    </h2>
    <p class="gl-text-subtle">
      {{ $options.i18n.description }}
    </p>

    <template v-if="isClassicAvailable">
      <div class="gl-flex gl-w-full gl-items-center gl-gap-3">
        <hr class="gl-my-0 gl-grow gl-border-default" />
        <span class="gl-text-subtle">{{ __('or') }}</span>
        <hr class="gl-my-0 gl-grow gl-border-default" />
      </div>
      <p class="gl-mb-0 gl-w-full gl-text-center gl-text-subtle">
        <gl-sprintf
          :message="
            s__(
              'DuoAgenticChat|%{linkStart}Use non-agentic Chat%{linkEnd} (answers questions only)',
            )
          "
        >
          <template #link="{ content }">
            <gl-button
              variant="link"
              data-testid="return-to-non-agentic-button"
              @click="$emit('return-to-classic')"
            >
              {{ content }}
            </gl-button>
          </template>
        </gl-sprintf>
      </p>
    </template>
  </div>
</template>
