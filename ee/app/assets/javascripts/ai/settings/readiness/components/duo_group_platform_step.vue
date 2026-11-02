<script>
import { GlButton, GlCollapsibleListbox, GlIcon, GlToggle } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { AVAILABILITY_OPTIONS } from '../../constants';
import { isLocked, lockIconProps, lockingGroup, stepStatus } from '../group_readiness';

const AVAILABILITY_ITEMS = [
  {
    value: AVAILABILITY_OPTIONS.ALWAYS_ON,
    text: s__('AiPowered|Always on'),
    help: s__(
      'DuoAgentPlatform|AI-native features are on for every project in this group. Subgroups and projects cannot opt out.',
    ),
  },
  {
    value: AVAILABILITY_OPTIONS.DEFAULT_ON,
    text: s__('AiPowered|On by default'),
    help: s__(
      'DuoAgentPlatform|AI-native features are on for every project in this group. Subgroups and projects can opt out individually.',
    ),
  },
  {
    value: AVAILABILITY_OPTIONS.DEFAULT_OFF,
    text: s__('AiPowered|Off by default'),
    help: s__(
      'DuoAgentPlatform|AI-native features are off for every project in this group. Subgroups and projects can opt in individually.',
    ),
  },
  {
    value: AVAILABILITY_OPTIONS.NEVER_ON,
    text: s__('AiPowered|Always off'),
    help: s__(
      'DuoAgentPlatform|AI-native features are off for every project in this group. Subgroups and projects cannot opt in.',
    ),
  },
];

const TOOL_APPROVAL_ITEMS = [
  { value: AVAILABILITY_OPTIONS.DEFAULT_ON, text: s__('AiPowered|On by default') },
  { value: AVAILABILITY_OPTIONS.DEFAULT_OFF, text: s__('AiPowered|Off by default') },
  { value: AVAILABILITY_OPTIONS.NEVER_ON, text: s__('AiPowered|Always off') },
];

const optionText = (items, value) => items.find((item) => item.value === value)?.text ?? '';

export default {
  name: 'DuoGroupPlatformStep',
  components: {
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    GlToggle,
    CascadingLockIcon,
    DuoReadinessRow,
  },
  inject: {
    isSaaS: { default: false },
    onGeneralSettingsPage: { default: false },
    showDuoAgentPlatformEnablementSetting: { default: false },
    duoAgentPlatformOwnerEnabled: { default: false },
    duoAgentPlatformOwnerSettingsPath: { default: null },
    rootAncestorName: { default: '' },
    duoAvailabilityCascadingSettings: { default: null },
    duoAvailabilityAdminLocked: { default: false },
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
    duoCoreFeaturesEnabled: {
      type: Boolean,
      required: true,
    },
    toolApprovalForSessionAvailability: {
      type: String,
      required: true,
    },
  },
  emits: [
    'change-duo-availability',
    'change-duo-agent-platform-enabled',
    'change-duo-core-features-enabled',
    'change-tool-approval-for-session',
  ],
  data() {
    return {
      noteId: uniqueId('duo-group-platform-note-'),
    };
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
    nestedDisabled() {
      return !this.platformOn;
    },
    nestedDescribedBy() {
      return this.showPlatformNote ? this.noteId : undefined;
    },
    duoLockState() {
      const cascadingSettings = this.duoAvailabilityCascadingSettings ?? {};

      return {
        ...cascadingSettings,
        lockedByAncestor: Boolean(cascadingSettings.lockedByAncestor),
        lockedByApplicationSetting:
          Boolean(cascadingSettings.lockedByApplicationSetting) || this.duoAvailabilityAdminLocked,
      };
    },
    duoLocked() {
      return isLocked(this.duoLockState);
    },
    toolApprovalLocked() {
      return isLocked(this.toolApprovalForSessionCascadingSettings);
    },
    duoToggleText() {
      return optionText(AVAILABILITY_ITEMS, this.duoAvailability);
    },
    duoDescription() {
      return AVAILABILITY_ITEMS.find((item) => item.value === this.duoAvailability)?.help ?? '';
    },
    duoInheritedNote() {
      if (!this.duoLocked) return null;

      const { i18n } = this.$options;

      if (this.duoLockState.lockedByApplicationSetting) {
        return sprintf(i18n.inheritedFromAdministrator, { value: this.duoToggleText });
      }

      return sprintf(i18n.inheritedFromGroupOwner, {
        value: this.duoToggleText,
        group: lockingGroup(this.duoLockState, this.rootAncestorName),
      });
    },
    // Only a group that owns the switch can act on the note; elsewhere the owner link
    // and the namespace notice say who controls it.
    showPlatformNote() {
      return this.showDuoAgentPlatformEnablementSetting && !this.platformOn;
    },
    ownerSettingsLinkText() {
      return this.isSaaS ? this.$options.i18n.groupSettings : this.$options.i18n.adminSettings;
    },
    toolApprovalToggleText() {
      return optionText(TOOL_APPROVAL_ITEMS, this.toolApprovalForSessionAvailability);
    },
  },
  methods: {
    lockIconProps,
    stepStatus,
  },
  AVAILABILITY_ITEMS,
  TOOL_APPROVAL_ITEMS,
  i18n: {
    platformTitle: s__('DuoAgentPlatform|Agent Platform'),
    seatlessAccessTitle: s__('DuoAgentPlatform|Seatless access'),
    inheritedFromAdministrator: s__(
      'DuoAgentPlatform|Inherited: %{value}, set by an instance administrator.',
    ),
    inheritedFromGroupOwner: s__(
      'DuoAgentPlatform|Inherited: %{value}, set by an Owner of %{group}.',
    ),
    groupSettings: s__('DuoAgentPlatform|Group settings'),
    adminSettings: s__('DuoAgentPlatform|Admin settings'),
  },
};
</script>

<template>
  <div>
    <duo-readiness-row
      :title="s__('DuoAgentPlatform|GitLab Duo')"
      :description="duoDescription"
      :status="stepStatus(duoOn)"
      data-testid="duo-row"
    >
      <template v-if="duoLocked" #title-icon>
        <cascading-lock-icon v-bind="lockIconProps(duoLockState)" class="gl-ml-1" />
      </template>
      <template v-if="duoInheritedNote" #note>
        <gl-icon name="lock" :size="12" class="gl-shrink-0" />
        <span>{{ duoInheritedNote }}</span>
      </template>
      <gl-collapsible-listbox
        :selected="duoAvailability"
        :items="$options.AVAILABILITY_ITEMS"
        :toggle-text="duoToggleText"
        :disabled="duoLocked"
        data-testid="duo-availability-listbox"
        @select="$emit('change-duo-availability', $event)"
      />
    </duo-readiness-row>

    <duo-readiness-row
      :title="$options.i18n.platformTitle"
      :description="s__('DuoAgentPlatform|Projects in this group can run agents and flows.')"
      :status="stepStatus(platformOn)"
      data-testid="platform-row"
    >
      <template v-if="showPlatformNote" #note>
        <span :id="noteId">{{
          s__('DuoAgentPlatform|Turn on Agent Platform to change the settings below.')
        }}</span>
      </template>
      <gl-toggle
        v-if="showDuoAgentPlatformEnablementSetting"
        :value="duoAgentPlatformEnabled"
        :label="$options.i18n.platformTitle"
        label-position="hidden"
        data-testid="platform-toggle"
        @change="$emit('change-duo-agent-platform-enabled', $event)"
      />
      <gl-button
        v-else-if="duoAgentPlatformOwnerSettingsPath"
        :category="platformOn ? 'tertiary' : 'secondary'"
        size="small"
        icon="external-link"
        :href="duoAgentPlatformOwnerSettingsPath"
        data-testid="platform-owner-link"
      >
        {{ ownerSettingsLinkText }}
      </gl-button>
    </duo-readiness-row>

    <duo-readiness-row
      v-if="!onGeneralSettingsPage"
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.seatlessAccessTitle"
      :description="
        s__(
          'DuoAgentPlatform|Users without a GitLab Duo Pro or Enterprise seat can use Agent Platform features.',
        )
      "
      :status="stepStatus(duoCoreFeaturesEnabled)"
      data-testid="seatless-access-row"
    >
      <gl-toggle
        :value="duoCoreFeaturesEnabled"
        :disabled="nestedDisabled"
        accessible-disabled
        :aria-describedby="nestedDescribedBy"
        :label="$options.i18n.seatlessAccessTitle"
        label-position="hidden"
        data-testid="seatless-access-toggle"
        @change="$emit('change-duo-core-features-enabled', $event)"
      />
    </duo-readiness-row>

    <duo-readiness-row
      nested
      :disabled="nestedDisabled"
      :title="s__('AiPowered|Tool approval for sessions')"
      :description="
        s__('DuoAgentPlatform|Users can approve tools for a whole session in their IDE or CLI.')
      "
      data-testid="tool-approval-row"
    >
      <template v-if="toolApprovalLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(toolApprovalForSessionCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
      <gl-collapsible-listbox
        :selected="toolApprovalForSessionAvailability"
        :items="$options.TOOL_APPROVAL_ITEMS"
        :toggle-text="toolApprovalToggleText"
        :disabled="nestedDisabled || toolApprovalLocked"
        data-testid="tool-approval-listbox"
        @select="$emit('change-tool-approval-for-session', $event)"
      />
    </duo-readiness-row>
  </div>
</template>
