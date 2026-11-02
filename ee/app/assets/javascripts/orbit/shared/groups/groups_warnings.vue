<script>
import { defineComponent } from 'vue';
import { GlAlert } from '@gitlab/ui';

export default defineComponent({
  name: 'OrbitGroupsWarnings',
  components: {
    GlAlert,
  },
  props: {
    indexStatusError: {
      type: String,
      required: false,
      default: null,
    },
    excludedGroupsError: {
      type: String,
      required: false,
      default: null,
    },
    canChangeGroups: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
});
</script>

<template>
  <div v-if="indexStatusError || excludedGroupsError" class="gl-flex gl-flex-col gl-gap-4">
    <gl-alert
      v-if="indexStatusError"
      variant="warning"
      :title="s__('Orbit|Index status is not available right now')"
      :dismissible="false"
      data-testid="orbit-index-status-error"
    >
      <p class="gl-mb-0">{{ indexStatusError }}</p>
      <p v-if="canChangeGroups" class="gl-mb-0 gl-mt-2">
        {{ s__('Orbit|You can still turn GitLab Orbit on or off.') }}
      </p>
    </gl-alert>
    <gl-alert
      v-if="excludedGroupsError"
      variant="warning"
      :title="s__('Orbit|Could not load excluded groups')"
      :dismissible="false"
      data-testid="orbit-excluded-error"
    >
      <p class="gl-mb-2">{{ excludedGroupsError }}</p>
      <p class="gl-mb-0">
        {{ s__('Orbit|Bulk actions are available after the excluded groups load.') }}
      </p>
    </gl-alert>
  </div>
</template>
