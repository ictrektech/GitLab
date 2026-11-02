<script>
export default {
  name: 'AgentSessionRetentionNotice',
  props: {
    sidePanel: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>
<template>
  <p
    :class="
      sidePanel
        ? 'gl-border-t gl-sticky gl-bottom-0 gl-z-2 gl-m-0 gl-mt-auto gl-bg-default gl-px-4 gl-py-3'
        : 'gl-mb-5 gl-mt-5'
    "
    class="gl-text-center gl-text-subtle"
    data-testid="retention-notice"
  >
    {{ s__('DuoAgentsPlatform|Inactive sessions are archived after 30 days.') }}
  </p>
</template>
