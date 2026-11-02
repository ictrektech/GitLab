<script>
import { defineComponent } from 'vue';
import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import ComponentHealthCard from '../../components/component_health_card.vue';
import { STATUS_DEGRADED, STATUS_HEALTHY, STATUS_MIGRATING } from '../../constants';

const HEALTH_LOADING = 'loading';
const HEALTH_AVAILABLE = 'available';
const HEALTH_DEGRADED = 'degraded';
const HEALTH_UNAVAILABLE = 'unavailable';
const HEALTH_LOAD_FAILED = 'loadFailed';

const HEALTH_VIEWS = {
  [HEALTH_LOADING]: {
    title: s__('Orbit|Checking the GitLab Orbit status…'),
    icon: null,
  },
  [HEALTH_AVAILABLE]: {
    title: s__('Orbit|GitLab Orbit service is running'),
    icon: { name: 'status-success', variant: 'success' },
  },
  [HEALTH_DEGRADED]: {
    title: s__('Orbit|GitLab Orbit service is degraded'),
    icon: { name: 'status-alert', variant: 'warning' },
  },
  [HEALTH_UNAVAILABLE]: {
    title: s__('Orbit|GitLab Orbit service is unavailable'),
    icon: { name: 'status-failed', variant: 'danger' },
  },
  [HEALTH_LOAD_FAILED]: {
    title: s__('Orbit|Could not check the GitLab Orbit status'),
    icon: { name: 'status-alert', variant: 'warning' },
  },
};

export default defineComponent({
  name: 'AdminHealthCard',
  components: {
    ComponentHealthCard,
    CrudComponent,
    GlIcon,
    GlLoadingIcon,
  },
  props: {
    status: {
      type: Object,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    loadError: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    health() {
      if (this.isLoading) return HEALTH_LOADING;
      if (this.loadError) return HEALTH_LOAD_FAILED;
      if ([STATUS_HEALTHY, STATUS_MIGRATING].includes(this.status.overall)) return HEALTH_AVAILABLE;
      if (this.status.overall === STATUS_DEGRADED) return HEALTH_DEGRADED;
      return HEALTH_UNAVAILABLE;
    },
    healthView() {
      return HEALTH_VIEWS[this.health];
    },
    isCollapsed() {
      return [HEALTH_LOADING, HEALTH_AVAILABLE].includes(this.health);
    },
    versionText() {
      return sprintf(s__('Orbit|Version %{version}'), { version: this.status.version });
    },
  },
});
</script>

<template>
  <crud-component
    :is-loading="isLoading"
    is-collapsible
    :collapsed="isCollapsed"
    actions-container-class="gl-self-center"
    data-testid="orbit-health-card"
  >
    <template #title>
      <span class="gl-flex gl-items-center gl-gap-3">
        <gl-icon
          v-if="healthView.icon"
          :name="healthView.icon.name"
          :variant="healthView.icon.variant"
          :size="16"
        />
        <gl-loading-icon v-else size="sm" />
        {{ healthView.title }}
      </span>
    </template>
    <template v-if="status.version" #actions>
      <span class="gl-font-monospace gl-text-sm gl-text-subtle">
        {{ versionText }}
      </span>
    </template>

    <p v-if="loadError" class="gl-mb-0 gl-text-subtle" data-testid="orbit-status-error">
      {{ loadError }}
    </p>
    <div v-else-if="status.components.length" class="gl-flex gl-flex-wrap gl-gap-3">
      <component-health-card
        v-for="component in status.components"
        :key="component.name"
        :component="component"
      />
    </div>
    <p v-else class="gl-mb-0 gl-text-subtle" data-testid="orbit-no-services">
      {{
        s__(
          'Orbit|GitLab Orbit did not report any services. Make sure the GitLab Orbit service is running and that GitLab can reach it.',
        )
      }}
    </p>
  </crud-component>
</template>
