<script>
import { defineComponent } from 'vue';
import { GlButton, GlLoadingIcon, GlPopover } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { formatNumber, n__, sprintf } from '~/locale';
import { pendingProjectCount } from 'ee/orbit/utils/orbit_group_state';

export default defineComponent({
  name: 'OverviewPendingProjects',
  components: { GlButton, GlLoadingIcon, GlPopover },
  props: {
    groups: {
      type: Array,
      required: true,
    },
  },
  computed: {
    pendingGroups() {
      return this.groups
        .map((group) => ({ id: group.id, name: group.name, count: pendingProjectCount(group) }))
        .filter(({ count }) => count > 0);
    },
    totalCount() {
      return this.pendingGroups.reduce((sum, { count }) => sum + count, 0);
    },
    buttonText() {
      return sprintf(
        n__('Orbit|Indexing %{count} project', 'Orbit|Indexing %{count} projects', this.totalCount),
        { count: formatNumber(this.totalCount) },
      );
    },
  },
  created() {
    this.buttonId = uniqueId('orbit-pending-projects-');
  },
  methods: {
    projectCountText(count) {
      return sprintf(n__('Orbit|%{count} project', 'Orbit|%{count} projects', count), {
        count: formatNumber(count),
      });
    },
  },
});
</script>

<template>
  <div>
    <gl-button :id="buttonId" size="small" data-testid="overview-pending-projects-button">
      <gl-loading-icon size="sm" inline aria-hidden="true" class="gl-mr-2" />{{ buttonText }}
    </gl-button>
    <gl-popover
      :target="buttonId"
      triggers="click blur"
      placement="bottom"
      :title="s__('Orbit|Indexing projects')"
    >
      <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0">
        <li
          v-for="group in pendingGroups"
          :key="group.id"
          class="gl-flex gl-justify-between gl-gap-4"
          data-testid="overview-pending-projects-group"
        >
          <span class="gl-min-w-0 gl-font-bold gl-wrap-anywhere">{{ group.name }}</span>
          <span class="gl-shrink-0">{{ projectCountText(group.count) }}</span>
        </li>
      </ul>
      <p class="gl-mb-0 gl-mt-3 gl-text-subtle">
        {{
          s__(
            'Orbit|They appear on the map when indexing finishes. Everything else is ready to query.',
          )
        }}
      </p>
    </gl-popover>
  </div>
</template>
