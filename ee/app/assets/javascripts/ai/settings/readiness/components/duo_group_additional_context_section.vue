<script>
import { GlButton, GlToggle } from '@gitlab/ui';
import { s__ } from '~/locale';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoReadinessSection from '~/ai/settings/readiness/components/duo_readiness_section.vue';
import { STATUS_DONE, STATUS_TODO } from '~/ai/settings/readiness/constants';
import DuoGroupReadinessMcpRow from './duo_group_readiness_mcp_row.vue';
import DuoReadinessOrbitRow from './duo_readiness_orbit_row.vue';

export default {
  name: 'DuoGroupAdditionalContextSection',
  components: {
    GlButton,
    GlToggle,
    DuoReadinessRow,
    DuoReadinessSection,
    DuoGroupReadinessMcpRow,
    DuoReadinessOrbitRow,
  },
  inject: {
    onGeneralSettingsPage: { default: false },
    groupFullPath: { default: null },
    duoOrbit: { default: () => ({}) },
    // Only a top-level group holds the IDE access setting; subgroups read it.
    duoWorkflowMcpRootEnabled: { default: false },
    duoAgentPlatformOwnerSettingsPath: { default: null },
    mcpServersAvailable: { default: false },
  },
  props: {
    // Whether this group can change IDE access: a top-level group whose owner
    // administers Duo Agent Platform, with the AI Catalog licensed.
    mcpAvailable: {
      type: Boolean,
      required: true,
    },
    mcpEnabled: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['mcp-change'],
  computed: {
    headingTag() {
      return this.onGeneralSettingsPage ? 'h4' : 'h2';
    },
    ideAccessOn() {
      return this.mcpAvailable ? this.mcpEnabled : this.duoWorkflowMcpRootEnabled;
    },
    ideAccessStatus() {
      return this.ideAccessOn ? STATUS_DONE : STATUS_TODO;
    },
    showOwnerLink() {
      return !this.mcpAvailable && Boolean(this.duoAgentPlatformOwnerSettingsPath);
    },
  },
  i18n: {
    // Doubles as the toggle label, so it stays shared.
    ideAccessTitle: s__('DuoAgentPlatform|IDE access'),
  },
};
</script>

<template>
  <duo-readiness-section
    :title="s__('DuoAgentPlatform|Additional context')"
    :subtitle="s__('DuoAgentPlatform|Features that give agents more context to work with.')"
    :heading-tag="headingTag"
    data-testid="additional-context-section"
  >
    <duo-readiness-orbit-row
      v-if="duoOrbit.rootGroupPath"
      group
      :orbit="duoOrbit"
      :full-path="groupFullPath"
    />

    <duo-group-readiness-mcp-row v-if="mcpServersAvailable" />

    <duo-readiness-row
      :title="$options.i18n.ideAccessTitle"
      :description="s__('DuoAgentPlatform|Allow the IDE to access external MCP tools.')"
      :status="ideAccessStatus"
      data-testid="ide-access-row"
    >
      <gl-toggle
        v-if="mcpAvailable"
        :value="mcpEnabled"
        :label="$options.i18n.ideAccessTitle"
        label-position="hidden"
        data-testid="ide-access-toggle"
        @change="$emit('mcp-change', $event)"
      />
      <gl-button
        v-else-if="showOwnerLink"
        category="tertiary"
        size="small"
        :href="duoAgentPlatformOwnerSettingsPath"
        data-testid="ide-access-view-button"
      >
        {{ s__('DuoAgentPlatform|View') }}
      </gl-button>
    </duo-readiness-row>
  </duo-readiness-section>
</template>
