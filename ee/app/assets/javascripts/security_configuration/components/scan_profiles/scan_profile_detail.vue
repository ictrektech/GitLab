<script>
import { GlBadge, GlButton, GlDisclosureDropdown, GlTooltipDirective } from '@gitlab/ui';
import { s__, __ } from '~/locale';
import { SCAN_PROFILE_I18N } from '~/security_configuration/constants';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import InsufficientPermissionsPopover from './insufficient_permissions_popover.vue';
import ScanTriggersDetail from './scan_triggers_detail.vue';
import AdvancedConfigurationTable from './advanced_configuration_table.vue';
import {
  scanTypeName,
  scanTypeHelpLink,
  resolveTriggers,
  classifyConfigurationVariables,
  managedByLabel,
} from './utils';
import { variableDefinitionsFor } from './variable_definitions';

const i18n = {
  generalDetails: s__('ScanProfiles|General details'),
  scanTriggers: s__('ScanProfiles|Scan triggers'),
  scanTriggersInfo: s__('ScanProfiles|When and how scans are run.'),
  advancedConfiguration: s__('ScanProfiles|Advanced configuration'),
  advancedConfigurationInfo: s__(
    'ScanProfiles|Variables passed to the analyzer that override its default behavior.',
  ),
  managedBy: s__('ScanProfiles|Managed by'),
  name: __('Name'),
  description: __('Description'),
  analyzerType: __('Analyzer type'),
  actions: s__('ScanProfiles|Profile actions'),
  edit: __('Edit'),
  duplicate: __('Duplicate'),
  delete: __('Delete'),
  managedDisallowed: s__(
    "ScanProfiles|GitLab-managed profiles can't be edited or deleted. Duplicate this profile to make a customized version.",
  ),
};

export default {
  name: 'ScanProfileDetail',
  components: {
    CrudComponent,
    GlBadge,
    GlButton,
    GlDisclosureDropdown,
    InsufficientPermissionsPopover,
    ScanTriggersDetail,
    AdvancedConfigurationTable,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: {
    rootGroupName: { default: '' },
  },
  props: {
    profile: {
      type: Object,
      required: true,
    },
    canCreate: {
      type: Boolean,
      required: false,
      default: false,
    },
    canUpdate: {
      type: Boolean,
      required: false,
      default: false,
    },
    canDelete: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['edit', 'duplicate', 'delete'],
  computed: {
    generalDetails() {
      return [
        { label: i18n.name, value: this.profile.name },
        { label: i18n.description, value: this.profile.description },
        { label: i18n.analyzerType, value: scanTypeName(this.profile.scanType) },
        {
          label: i18n.managedBy,
          value: managedByLabel(this.profile, this.rootGroupName),
          isBadge: true,
        },
      ];
    },
    profileHelpLink() {
      return scanTypeHelpLink(this.profile.scanType);
    },
    variableDefinitions() {
      return variableDefinitionsFor(this.profile.scanType);
    },
    advancedConfiguration() {
      return classifyConfigurationVariables({
        scanType: this.profile.scanType,
        triggers: this.profile.triggers ?? [],
        triggerSettings: this.profile.triggerSettings ?? [],
      });
    },
    triggers() {
      return resolveTriggers(this.profile.triggers, this.profile.scanType).map((definition) => ({
        ...definition,
        variableRows: this.advancedConfiguration.rowsByTrigger.get(definition.triggerType) ?? [],
      }));
    },
    hasEnabledTriggers() {
      return (this.profile.triggers ?? []).length > 0;
    },
    canManage() {
      return !this.profile.gitlabRecommended && (this.canUpdate || this.canDelete);
    },
    showPermissionsPopover() {
      return !this.profile.gitlabRecommended && !this.canManage;
    },
    actionsTooltip() {
      return this.profile.gitlabRecommended ? i18n.managedDisallowed : '';
    },
    deniedActionItems() {
      return this.canManage ? this.actionItems.filter(({ disabled }) => disabled) : [];
    },
    actionItems() {
      return [
        {
          text: i18n.edit,
          action: () => this.canUpdate && this.$emit('edit'),
          disabled: !this.canUpdate,
          wrapperClass: 'js-scan-profile-edit-item',
          deniedDescription: SCAN_PROFILE_I18N.noUpdatePermission,
          extraAttrs: { 'data-testid': 'scan-profile-edit-action' },
        },
        {
          text: i18n.delete,
          action: () => this.canDelete && this.$emit('delete'),
          variant: 'danger',
          disabled: !this.canDelete,
          wrapperClass: 'js-scan-profile-delete-item',
          deniedDescription: SCAN_PROFILE_I18N.noDeletePermission,
          extraAttrs: { 'data-testid': 'scan-profile-delete-action' },
        },
      ];
    },
  },
  i18n,
  SCAN_PROFILE_I18N,
};
</script>

<template>
  <div data-testid="scan-profile-detail">
    <div class="gl-flex gl-items-start gl-justify-between gl-gap-3">
      <h3 class="gl-heading-3">{{ profile.name }}</h3>
      <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-3">
        <div ref="duplicateWrapper" data-testid="scan-profile-duplicate-wrapper">
          <gl-button
            :disabled="!canCreate"
            data-testid="scan-profile-duplicate-action"
            @click="$emit('duplicate')"
          >
            {{ $options.i18n.duplicate }}
          </gl-button>
          <insufficient-permissions-popover
            v-if="!canCreate"
            :target="() => $refs.duplicateWrapper"
            :description="$options.SCAN_PROFILE_I18N.noCreatePermission"
          />
        </div>
        <div
          ref="actionsWrapper"
          v-gl-tooltip
          :title="actionsTooltip"
          class="gl-flex gl-items-center"
          data-testid="scan-profile-actions-wrapper"
        >
          <gl-disclosure-dropdown
            :items="actionItems"
            :toggle-text="$options.i18n.actions"
            text-sr-only
            icon="ellipsis_v"
            no-caret
            category="tertiary"
            placement="bottom-end"
            :disabled="!canManage"
            data-testid="scan-profile-actions-dropdown"
          />
          <insufficient-permissions-popover
            v-if="showPermissionsPopover"
            :target="() => $refs.actionsWrapper"
            :description="$options.SCAN_PROFILE_I18N.noManagePermission"
          />
          <insufficient-permissions-popover
            v-for="item in deniedActionItems"
            :key="item.wrapperClass"
            :target="() => $el.querySelector(`.${item.wrapperClass}`)"
            :description="item.deniedDescription"
          />
        </div>
      </div>
    </div>

    <crud-component class="gl-mb-5" :title="$options.i18n.generalDetails">
      <dl class="gl-m-0 gl-flex gl-flex-col gl-gap-3">
        <div
          v-for="{ label, value, isBadge } in generalDetails"
          :key="label"
          class="gl-flex gl-gap-3"
        >
          <dt class="gl-w-1/3 gl-font-normal gl-text-subtle">{{ label }}</dt>
          <dd class="gl-m-0 gl-flex-1">
            <gl-badge v-if="isBadge">{{ value }}</gl-badge>
            <template v-else>{{ value }}</template>
          </dd>
        </div>
      </dl>
    </crud-component>

    <h4 class="gl-heading-4 gl-mb-1">{{ $options.i18n.scanTriggers }}</h4>
    <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.scanTriggersInfo }}</p>
    <scan-triggers-detail
      :profile-help-link="profileHelpLink"
      :triggers="triggers"
      :variable-definitions="variableDefinitions"
    />

    <template v-if="hasEnabledTriggers && !profile.gitlabRecommended">
      <h4 class="gl-heading-4 gl-mb-1 gl-mt-5">{{ $options.i18n.advancedConfiguration }}</h4>
      <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.advancedConfigurationInfo }}</p>
      <advanced-configuration-table
        v-if="advancedConfiguration.profileRows.length"
        :caption="s__('ScanProfiles|Settings that apply across this profile')"
        :rows="advancedConfiguration.profileRows"
        :variable-definitions="variableDefinitions"
      />
      <p
        v-else-if="!advancedConfiguration.hasConfigurableTriggers"
        class="gl-text-subtle"
        data-testid="scan-profile-advanced-configuration-nothing-to-configure"
      >
        {{
          s__(
            "ScanProfiles|None of this profile's triggers use analyzer settings, so there is nothing to configure.",
          )
        }}
      </p>
      <p v-else class="gl-text-subtle" data-testid="scan-profile-advanced-configuration-empty">
        {{ s__('ScanProfiles|No advanced configuration is set for this profile.') }}
      </p>
    </template>
  </div>
</template>
