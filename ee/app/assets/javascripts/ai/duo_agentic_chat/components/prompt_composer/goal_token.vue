<script>
import { GlIcon, GlToken } from '@gitlab/ui';
import { s__ } from '~/locale';

/**
 * Stands in for the `/goal` command once goal mode is on, in place of the token the
 * user typed. The prompt underneath is then free for the goal itself, which is what
 * the composer's placeholder asks for.
 */
export default {
  name: 'GoalToken',
  components: {
    GlIcon,
    GlToken,
  },
  props: {
    viewOnly: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['remove'],
  i18n: {
    GOAL: s__('DuoAgenticChat|Goal'),
    REMOVE: s__('DuoAgenticChat|Remove goal'),
  },
};
</script>
<template>
  <gl-token
    class="gl-max-w-full gl-bg-alpha-light-16 dark:gl-bg-alpha-dark-40"
    :view-only="viewOnly"
    :remove-label="$options.i18n.REMOVE"
    data-testid="goal-token"
    @close="$emit('remove')"
  >
    <span class="gl-flex gl-items-center gl-gap-2">
      <gl-icon name="work-item-objective" :size="12" variant="current" />
      {{ $options.i18n.GOAL }}
    </span>
  </gl-token>
</template>
