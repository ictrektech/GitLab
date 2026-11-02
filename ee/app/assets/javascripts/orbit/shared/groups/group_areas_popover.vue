<script>
import { defineComponent } from 'vue';
import { GlButton, GlIcon, GlLoadingIcon, GlPopover } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';

export default defineComponent({
  name: 'OrbitGroupAreasPopover',
  components: { GlButton, GlIcon, GlLoadingIcon, GlPopover },
  props: {
    toggleId: {
      type: String,
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
    areas: {
      type: Array,
      required: true,
    },
  },
  computed: {
    toggleLabel() {
      return sprintf(
        s__('Orbit|Index status by area for %{group}'),
        { group: this.groupName },
        false,
      );
    },
  },
});
</script>

<template>
  <span class="gl-inline-flex">
    <gl-button
      :id="toggleId"
      :aria-label="toggleLabel"
      category="tertiary"
      size="small"
      icon="information-o"
      data-testid="group-areas-toggle"
    />
    <gl-popover :target="toggleId" :title="groupName" data-testid="group-areas">
      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li v-for="area in areas" :key="area.key" class="gl-flex gl-items-center gl-gap-3 gl-py-1">
          <gl-loading-icon v-if="area.isIndexing" size="sm" inline />
          <gl-icon v-else :name="area.icon" :variant="area.iconVariant" />
          <span class="gl-grow">{{ area.label }}</span>
          <span class="gl-text-subtle">{{ area.stateLabel }}</span>
        </li>
      </ul>
    </gl-popover>
  </span>
</template>
