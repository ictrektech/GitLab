<script>
import { GlToggle } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { CODE_REVIEW_FLOW_REFERENCE } from '../../constants';
import FoundationalFlowPicker from '../../components/foundational_flow_picker.vue';
import { isLocked, lockIconProps, stepStatus } from '../group_readiness';
import DuoGroupReadinessRunnerRow from './duo_group_readiness_runner_row.vue';

export default {
  name: 'DuoGroupFlowsStep',
  components: {
    GlToggle,
    CascadingLockIcon,
    DuoReadinessRow,
    DuoGroupReadinessRunnerRow,
    FoundationalFlowPicker,
  },
  inject: {
    duoRemoteFlowsCascadingSettings: { default: null },
    duoFoundationalFlowsCascadingSettings: { default: null },
    duoCustomFlowsCascadingSettings: { default: null },
    groupIsRoot: { default: true },
    rootAncestorName: { default: '' },
    availableFoundationalFlows: { default: () => [] },
    duoEnterpriseActive: { default: false },
    initialCodeReviewFlowConsentGiven: { default: false },
  },
  props: {
    remoteFlowsEnabled: {
      type: Boolean,
      required: true,
    },
    foundationalFlowsEnabled: {
      type: Boolean,
      required: true,
    },
    customFlowsEnabled: {
      type: Boolean,
      required: true,
    },
    selectedFoundationalFlowIds: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: [
    'change-remote-flows-enabled',
    'change-foundational-flows-enabled',
    'change-custom-flows-enabled',
    'change-selected-flow-ids',
    'consent-given',
    'runner-confirmed',
  ],
  data() {
    return {
      noteId: uniqueId('duo-group-flows-note-'),
      codeReviewConsentGiven: this.initialCodeReviewFlowConsentGiven,
    };
  },
  computed: {
    // A subgroup is sent only the flows its top-level group picked.
    flowsSelected() {
      if (this.groupIsRoot) return this.selectedFoundationalFlowIds.length > 0;

      return this.availableFoundationalFlows.length > 0;
    },
    // The setting is written from the selection, but turning the platform off keeps the
    // selection while the setting goes off, so the status needs both.
    foundationalFlowsOn() {
      return this.remoteFlowsEnabled && this.foundationalFlowsEnabled && this.flowsSelected;
    },
    customFlowsOn() {
      return this.remoteFlowsEnabled && this.customFlowsEnabled;
    },
    nestedDisabled() {
      return !this.remoteFlowsEnabled;
    },
    remoteFlowsLocked() {
      return isLocked(this.duoRemoteFlowsCascadingSettings);
    },
    foundationalFlowsLocked() {
      return isLocked(this.duoFoundationalFlowsCascadingSettings);
    },
    customFlowsLocked() {
      return isLocked(this.duoCustomFlowsCascadingSettings);
    },
    showFlowsNote() {
      return !this.remoteFlowsEnabled && !this.remoteFlowsLocked;
    },
    nestedDescribedBy() {
      return this.showFlowsNote ? this.noteId : undefined;
    },
    // Only the top-level group picks flows; a subgroup shows the flows it picked.
    showFlowPicker() {
      return this.groupIsRoot && this.availableFoundationalFlows.length > 0;
    },
    foundationalFlowsDescription() {
      if (this.groupIsRoot) return this.$options.i18n.foundationalFlowsDescription;

      return sprintf(
        this.$options.i18n.foundationalFlowsInheritedDescription,
        { group: this.rootAncestorName },
        false,
      );
    },
    // Code Review stays out of the default while it still needs its consent dialog.
    defaultFlowSelection() {
      const consentNeeded = this.duoEnterpriseActive && !this.codeReviewConsentGiven;

      return this.availableFoundationalFlows
        .map((flow) => flow.reference)
        .filter((reference) => !consentNeeded || reference !== CODE_REVIEW_FLOW_REFERENCE);
    },
  },
  methods: {
    lockIconProps,
    stepStatus,
    onConsentGiven() {
      this.codeReviewConsentGiven = true;
      this.$emit('consent-given');
    },
    onRemoteFlowsChanged(value) {
      this.$emit('change-remote-flows-enabled', value);

      if (!value || !this.showFlowPicker || this.foundationalFlowsLocked) return;

      if (this.flowsSelected) {
        // Flows picked earlier come back on with Flow execution.
        if (!this.foundationalFlowsEnabled) this.$emit('change-foundational-flows-enabled', true);
        return;
      }

      // First setup selects every flow as a real list: an empty list means "use the
      // parent group's flows", so saving it would turn nothing on.
      this.onFlowSelectionChanged(this.defaultFlowSelection);
    },
    onFlowSelectionChanged(flowIds) {
      this.$emit('change-selected-flow-ids', flowIds);

      const enabled = flowIds.length > 0;
      if (enabled !== this.foundationalFlowsEnabled) {
        this.$emit('change-foundational-flows-enabled', enabled);
      }
    },
  },
  // Descriptions are definitions and stay put when a toggle moves — the toggle
  // already says on or off, and the section subtitle carries the lock warning.
  i18n: {
    flowExecutionTitle: s__('DuoAgentPlatform|Flow execution'),
    flowExecutionDescription: s__(
      'DuoAgentPlatform|Flows combine one or more agents to solve a complex problem.',
    ),
    foundationalFlowsTitle: s__('DuoAgentPlatform|Foundational flows'),
    foundationalFlowsDescription: s__(
      'DuoAgentPlatform|Projects in this group can use flows built and maintained by GitLab.',
    ),
    foundationalFlowsInheritedDescription: s__(
      'DuoAgentPlatform|Projects in this group can use these flows built and maintained by GitLab. Set by %{group}.',
    ),
    customFlowsTitle: s__('DuoAgentPlatform|Custom flows'),
    customFlowsDescription: s__(
      'AiPowered|Users with the Maintainer or Owner role for a project can create new flows.',
    ),
  },
};
</script>

<template>
  <div>
    <duo-readiness-row
      :title="$options.i18n.flowExecutionTitle"
      :description="$options.i18n.flowExecutionDescription"
      :status="stepStatus(remoteFlowsEnabled)"
      data-testid="flow-execution-row"
    >
      <template v-if="remoteFlowsLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(duoRemoteFlowsCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
      <template v-if="showFlowsNote" #note>
        <span :id="noteId">{{
          s__(
            'DuoAgentPlatform|Turn on Flow execution to change Foundational flows and Custom flows.',
          )
        }}</span>
      </template>
      <gl-toggle
        :value="remoteFlowsEnabled"
        :disabled="remoteFlowsLocked"
        :label="$options.i18n.flowExecutionTitle"
        label-position="hidden"
        data-testid="flow-execution-toggle"
        @change="onRemoteFlowsChanged"
      />
    </duo-readiness-row>

    <duo-group-readiness-runner-row nested @runner-confirmed="$emit('runner-confirmed', $event)" />

    <duo-readiness-row
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.foundationalFlowsTitle"
      :description="foundationalFlowsDescription"
      :status="stepStatus(foundationalFlowsOn)"
      data-testid="foundational-flows-row"
    >
      <template v-if="foundationalFlowsLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(duoFoundationalFlowsCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
    </duo-readiness-row>

    <div
      v-if="showFlowPicker"
      class="gl-border-t gl-bg-subtle gl-py-3 gl-pl-9 gl-pr-4"
      data-testid="foundational-flow-picker-row"
    >
      <foundational-flow-picker
        select-all
        :value="selectedFoundationalFlowIds"
        :disabled="nestedDisabled || foundationalFlowsLocked"
        :described-by="nestedDescribedBy"
        @input="onFlowSelectionChanged"
        @consent-given="onConsentGiven"
      />
    </div>
    <div
      v-else-if="availableFoundationalFlows.length"
      class="gl-border-t gl-bg-subtle gl-py-3 gl-pl-9 gl-pr-4"
      data-testid="foundational-flow-list-row"
    >
      <ul
        class="gl-m-0 gl-list-none gl-p-0 gl-text-sm"
        :class="{ 'gl-text-subtle': nestedDisabled }"
      >
        <li v-for="flow in availableFoundationalFlows" :key="flow.reference" class="gl-py-1">
          {{ flow.name }}
        </li>
      </ul>
    </div>

    <duo-readiness-row
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.customFlowsTitle"
      :description="$options.i18n.customFlowsDescription"
      :status="stepStatus(customFlowsOn)"
      data-testid="custom-flows-row"
    >
      <template v-if="customFlowsLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(duoCustomFlowsCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
      <gl-toggle
        :value="customFlowsOn"
        :disabled="nestedDisabled || customFlowsLocked"
        :accessible-disabled="!customFlowsLocked"
        :aria-describedby="nestedDescribedBy"
        :label="$options.i18n.customFlowsTitle"
        label-position="hidden"
        data-testid="custom-flows-toggle"
        @change="$emit('change-custom-flows-enabled', $event)"
      />
    </duo-readiness-row>
  </div>
</template>
