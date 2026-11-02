<script>
import { GlAlert, GlIcon, GlProgressBar } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { glSlotsMixin } from '~/lib/utils/vue3compat/gl_slots_mixin';
import DuoReadinessSection from '~/ai/settings/readiness/components/duo_readiness_section.vue';
import { AVAILABILITY_OPTIONS } from '../../constants';
import {
  STEP_COUNT,
  SETUP_COMPLETE,
  SETUP_RUNNER_NEEDED,
  isLocked,
  lockingGroup,
  readinessSummary,
} from '../group_readiness';

export default {
  name: 'DuoGroupReadinessCard',
  components: {
    GlAlert,
    GlIcon,
    GlProgressBar,
    DuoReadinessSection,
  },
  mixins: [glSlotsMixin],
  inject: {
    isSaaS: { default: false },
    onGeneralSettingsPage: { default: false },
    showDuoAgentPlatformEnablementSetting: { default: false },
    showFoundationalAgentsAvailability: { default: false },
    duoAgentPlatformOwnerEnabled: { default: false },
    foundationalAgentsOwnerEnabled: { default: false },
    rootAncestorName: { default: '' },
    duoAvailabilityCascadingSettings: { default: null },
    duoAvailabilityAdminLocked: { default: false },
    duoRemoteFlowsCascadingSettings: { default: null },
    duoFoundationalFlowsCascadingSettings: { default: null },
    duoCustomAgentsCascadingSettings: { default: null },
    duoCustomFlowsCascadingSettings: { default: null },
    duoExternalAgentsCascadingSettings: { default: null },
    toolApprovalForSessionCascadingSettings: { default: null },
  },
  props: {
    duoAvailability: {
      type: String,
      required: true,
    },
    duoAgentPlatformEnabled: {
      type: Boolean,
      required: true,
    },
    foundationalAgentsEnabled: {
      type: Boolean,
      required: true,
    },
    remoteFlowsEnabled: {
      type: Boolean,
      required: true,
    },
    runnerConfirmed: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    duoOn() {
      return this.duoAvailability !== AVAILABILITY_OPTIONS.NEVER_ON;
    },
    platformOn() {
      return this.showDuoAgentPlatformEnablementSetting
        ? this.duoAgentPlatformEnabled
        : this.duoAgentPlatformOwnerEnabled;
    },
    platformOffAtOwner() {
      return !this.showDuoAgentPlatformEnablementSetting && !this.duoAgentPlatformOwnerEnabled;
    },
    agentsOn() {
      return this.showFoundationalAgentsAvailability
        ? this.foundationalAgentsEnabled
        : this.foundationalAgentsOwnerEnabled;
    },
    duoLocked() {
      return isLocked(this.duoAvailabilityCascadingSettings) || this.duoAvailabilityAdminLocked;
    },
    flowsLocked() {
      return isLocked(this.duoRemoteFlowsCascadingSettings);
    },
    duoLockedBy() {
      return lockingGroup(this.duoAvailabilityCascadingSettings, this.rootAncestorName);
    },
    flowsLockedBy() {
      return lockingGroup(this.duoRemoteFlowsCascadingSettings, this.rootAncestorName);
    },
    summary() {
      return readinessSummary({
        duoOn: this.duoOn,
        platformOn: this.platformOn,
        agentsOn: this.agentsOn,
        flowsOn: this.remoteFlowsEnabled,
        platformOffAtOwner: this.platformOffAtOwner,
        runnerConfirmed: this.runnerConfirmed,
        duoLocked: this.duoLocked,
        flowsLocked: this.flowsLocked,
        duoLockedBy: this.duoLockedBy,
        flowsLockedBy: this.flowsLockedBy,
        isSaaS: this.isSaaS,
        rootAncestorName: this.rootAncestorName,
      });
    },
    stateLineText() {
      // Status first, then who turned the rest off.
      return [this.summary.stateLine, this.summary.lockedNote].filter(Boolean).join(' ');
    },
    runnerNeeded() {
      return this.summary.status === SETUP_RUNNER_NEEDED;
    },
    progressVariant() {
      if (this.summary.status === SETUP_COMPLETE) return 'success';

      return this.runnerNeeded ? 'warning' : 'primary';
    },
    headingTag() {
      return this.onGeneralSettingsPage ? 'h3' : 'h1';
    },
    headingClass() {
      return this.onGeneralSettingsPage ? 'gl-heading-3' : 'gl-heading-1';
    },
    sectionHeadingTag() {
      return this.onGeneralSettingsPage ? 'h4' : 'h2';
    },
    lockedByAncestor() {
      return [
        this.duoAvailabilityCascadingSettings,
        this.duoRemoteFlowsCascadingSettings,
        this.duoFoundationalFlowsCascadingSettings,
        this.duoCustomAgentsCascadingSettings,
        this.duoCustomFlowsCascadingSettings,
        this.duoExternalAgentsCascadingSettings,
        this.toolApprovalForSessionCascadingSettings,
      ].some((cascadingSettings) => cascadingSettings?.lockedByAncestor);
    },
    namespaceNotice() {
      if (!this.isSaaS) {
        return {
          title: s__('DuoAgentPlatform|Agent Platform is controlled at the instance level'),
          body: s__(
            "DuoAgentPlatform|An instance administrator turns on Agent Platform, Orbit, and MCP tools for every group on the instance. It can't be set here.",
          ),
        };
      }
      if (this.lockedByAncestor) {
        const group = this.rootAncestorName;

        return {
          title: sprintf(s__('DuoAgentPlatform|Inherited from %{group}'), { group }),
          body: sprintf(
            s__(
              'DuoAgentPlatform|Some settings are set by %{group}. To change them, ask an Owner of %{group}.',
            ),
            { group },
          ),
        };
      }

      return null;
    },
  },
  STEP_COUNT,
};
</script>

<template>
  <div class="gl-mb-6" data-testid="duo-group-readiness-card">
    <div class="gl-mb-5 gl-flex gl-items-start gl-justify-between gl-gap-5">
      <div class="gl-min-w-0">
        <component
          :is="headingTag"
          class="gl-mb-2"
          :class="headingClass"
          data-testid="readiness-heading"
        >
          {{ s__('DuoAgentPlatform|Run GitLab Duo agents and flows in this group') }}
        </component>
        <p aria-live="polite" class="gl-mb-0 gl-text-subtle" data-testid="readiness-state-line">
          {{ stateLineText }}
        </p>
      </div>
      <div class="gl-w-1/4 gl-shrink-0 gl-text-right">
        <span
          class="gl-inline-flex gl-items-center gl-gap-2 gl-text-sm"
          :class="runnerNeeded ? 'gl-text-warning' : 'gl-text-subtle'"
          data-testid="readiness-progress-count"
        >
          <gl-icon
            v-if="runnerNeeded"
            name="warning"
            variant="warning"
            :size="12"
            data-testid="readiness-progress-warning"
          />
          <span>{{ summary.progressLabel }}</span>
        </span>
        <gl-progress-bar
          :value="summary.doneCount"
          :max="$options.STEP_COUNT"
          :aria-label="summary.progressBarLabel"
          :variant="progressVariant"
          class="gl-mt-2"
          data-testid="readiness-progress-bar"
        />
      </div>
    </div>

    <gl-alert
      v-if="namespaceNotice"
      variant="info"
      :dismissible="false"
      :title="namespaceNotice.title"
      class="gl-mb-5"
      data-testid="namespace-notice"
    >
      {{ namespaceNotice.body }}
    </gl-alert>

    <duo-readiness-section
      :title="s__('DuoAgentPlatform|Agent and flow setup')"
      :subtitle="
        s__(
          'DuoAgentPlatform|Projects in this group follow these settings. If you turn one off, projects can\'t turn it on.',
        )
      "
      :heading-tag="sectionHeadingTag"
    >
      <template v-if="glSlots().default" #default>
        <slot></slot>
      </template>
    </duo-readiness-section>
  </div>
</template>
