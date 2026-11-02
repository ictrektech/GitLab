<script>
import {
  GlTableLite,
  GlButtonGroup,
  GlButton,
  GlCollapsibleListbox,
  GlIcon,
  GlTooltipDirective,
  GlLink,
  GlPopover,
  GlBadge,
} from '@gitlab/ui';
import { groupBy } from 'lodash-es';
import { __ } from '~/locale';
import { InternalEvents } from '~/tracking';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import {
  SCAN_PROFILE_STATUS_APPLIED,
  SCAN_PROFILE_STATUS_MIXED,
  SCAN_PROFILE_STATUS_DISABLED,
  SCAN_PROFILE_CATEGORIES,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
  SCAN_PROFILE_I18N,
  EVENT_VIEW_SCAN_PROFILE_TABLE,
} from '~/security_configuration/constants';
import {
  managedByLabel,
  getDefaultProfile,
  isScanProfileTypeVisible,
} from 'ee/security_configuration/components/scan_profiles/utils';
import AvailableSecurityScanProfiles from '../graphql/available_security_scan_profiles.query.graphql';
import {
  SCANNER_TYPES,
  SECRET_DETECTION_KEY,
  SAST_KEY,
  DEPENDENCY_SCANNING_KEY,
  BUSINESS_LOGIC_KEY,
  SKILLGUARD_KEY,
} from '../constants';

export default {
  name: 'BulkScannerProfileConfiguration',
  components: {
    CrudComponent,
    GlTableLite,
    GlButtonGroup,
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    GlLink,
    GlPopover,
    GlBadge,
  },
  directives: { GlTooltip: GlTooltipDirective },
  mixins: [InternalEvents.mixin()],
  inject: {
    groupFullPath: {},
    rootGroupName: { default: '' },
  },
  props: {
    statusPatches: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    lastStatusPatch: {
      type: String,
      required: false,
      default: () => '',
    },
  },
  emits: ['attach-profile', 'detach-profile', 'preview-profile'],
  data() {
    return {
      availableSecurityScanProfiles: [],
      selectedProfileIds: {},
    };
  },
  apollo: {
    availableSecurityScanProfiles: {
      query: AvailableSecurityScanProfiles,
      variables() {
        return {
          fullPath: this.groupFullPath,
        };
      },
      update: (data) =>
        (data?.group?.availableSecurityScanProfiles ?? []).filter((profile) =>
          isScanProfileTypeVisible(profile.scanType),
        ),
    },
  },
  computed: {
    scanTypeLabel() {
      return (scanType) => this.$options.SCANNER_CATEGORIES[scanType]?.label || '';
    },
    scanTypeName() {
      return (scanType) => this.$options.SCANNER_CATEGORIES[scanType]?.name || __('Unknown');
    },
    profileGroups() {
      return groupBy(this.availableSecurityScanProfiles, 'scanType');
    },
    rows() {
      // eslint-disable-next-line no-unused-expressions -- used to trigger re-render
      this.lastStatusPatch;

      return Object.entries(this.profileGroups).map(([scanType, profiles]) => {
        const recommended = getDefaultProfile(scanType, profiles);
        const selectedId = this.selectedProfileIds[scanType] ?? recommended.id;
        const selectedProfile =
          profiles.find((profile) => profile.id === selectedId) ?? recommended;
        return {
          ...selectedProfile,
          ...this.statusPatches[selectedProfile.id],
          scanType,
          profiles,
          hasMultipleProfiles: profiles.length > 1,
        };
      });
    },
  },
  mounted() {
    this.trackEvent(EVENT_VIEW_SCAN_PROFILE_TABLE);
  },
  methods: {
    managedByLabel,
    profileText(profile) {
      if (profile.status === SCAN_PROFILE_STATUS_MIXED) {
        return __('Mixed');
      }
      return profile.name;
    },
    showsManagedByBadge(item) {
      return (
        item.status === SCAN_PROFILE_STATUS_APPLIED ||
        (item.status !== SCAN_PROFILE_STATUS_MIXED && !item.hasMultipleProfiles)
      );
    },
    selectProfile(scanType, profileId) {
      this.selectedProfileIds = { ...this.selectedProfileIds, [scanType]: profileId };
    },
    listboxItems(profiles) {
      return profiles.map((profile) => ({ value: profile.id, text: profile.name, profile }));
    },
    applyButtonLabel(item) {
      return item.gitlabRecommended
        ? SCAN_PROFILE_I18N.applyDefaultToAll
        : SCAN_PROFILE_I18N.applyProfileToAll;
    },
    previewButtonLabel(item) {
      return item.gitlabRecommended
        ? SCAN_PROFILE_I18N.previewDefault
        : SCAN_PROFILE_I18N.previewProfile;
    },
    statusClasses(status) {
      switch (status) {
        case SCAN_PROFILE_STATUS_APPLIED:
          return 'gl-bg-green-100 gl-border-green-500 gl-text-green-800';
        case SCAN_PROFILE_STATUS_DISABLED:
          return 'gl-bg-feedback-danger gl-border-feedback-danger gl-text-feedback-danger';
        case SCAN_PROFILE_STATUS_MIXED:
        default:
          return 'gl-bg-feedback-neutral gl-border-feedback-neutral gl-text-feedback-neutral';
      }
    },
  },
  SCANNER_CATEGORIES: {
    SECRET_DETECTION: {
      name: SCANNER_TYPES[SECRET_DETECTION_KEY].name,
      label: SCANNER_TYPES[SECRET_DETECTION_KEY].textLabel,
    },
    SAST: {
      name: SCANNER_TYPES[SAST_KEY].name,
      label: SCANNER_TYPES[SAST_KEY].textLabel,
    },
    DEPENDENCY_SCANNING: {
      name: SCANNER_TYPES[DEPENDENCY_SCANNING_KEY].name,
      label: SCANNER_TYPES[DEPENDENCY_SCANNING_KEY].textLabel,
    },
    BUSINESS_LOGIC: {
      name: SCANNER_TYPES[BUSINESS_LOGIC_KEY].name,
      label: SCANNER_TYPES[BUSINESS_LOGIC_KEY].textLabel,
    },
    TRIAGE_AND_REMEDIATION: {
      name: SCAN_PROFILE_CATEGORIES[SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION].name,
      label: SCAN_PROFILE_CATEGORIES[SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION].label,
    },
    SKILLGUARD: {
      name: SCANNER_TYPES[SKILLGUARD_KEY].name,
      label: SCANNER_TYPES[SKILLGUARD_KEY].textLabel,
    },
  },
  fields: [
    {
      key: 'scanType',
      label: __('Scanner'),
    },
    {
      key: 'name',
      label: __('Profile'),
    },
    {
      key: 'actions',
      label: '',
      tdClass: '!gl-border-t-0',
    },
  ],
  SCAN_PROFILE_STATUS_APPLIED,
  SCAN_PROFILE_STATUS_MIXED,
  SCAN_PROFILE_STATUS_DISABLED,
};
</script>

<template>
  <div>
    <crud-component header-class="gl-hidden">
      <gl-table-lite :items="rows" :fields="$options.fields" stacked="md">
        <template #cell(scanType)="{ item }">
          <div data-testid="scan-type-cell" class="gl-flex gl-items-center">
            <div
              class="gl-border gl-mr-3 gl-flex gl-items-center gl-justify-center gl-rounded-lg gl-p-2"
              :class="statusClasses(item.status)"
              data-testid="scan-type-icon"
              style="width: 32px; height: 32px"
            >
              <span class="gl-font-weight-bold gl-text-xs">
                {{ scanTypeLabel(item.scanType) }}
              </span>
            </div>
            <span :id="`${item.scanType}-scanner-name`" class="gl-font-bold">
              {{ scanTypeName(item.scanType) }}
            </span>
          </div>
        </template>

        <template #cell(name)="{ item }">
          <div data-testid="profile-name-cell" class="gl-flex gl-flex-col">
            <div class="gl-flex gl-h-7 gl-items-center">
              <span
                v-if="item.status === $options.SCAN_PROFILE_STATUS_DISABLED"
                class="gl-sr-only"
                data-testid="disabled-status-sr-label"
                >{{ __('Disabled') }}</span
              >
              <gl-link
                v-if="item.status === $options.SCAN_PROFILE_STATUS_APPLIED"
                @click="$emit('preview-profile', item)"
              >
                {{ profileText(item) }}
              </gl-link>
              <gl-collapsible-listbox
                v-else-if="item.hasMultipleProfiles"
                data-testid="profile-picker"
                :items="listboxItems(item.profiles)"
                :selected="item.id"
                :toggle-text="item.name"
                :toggle-aria-labelled-by="`${item.scanType}-scanner-name`"
                @select="(profileId) => selectProfile(item.scanType, profileId)"
              >
                <template #list-item="{ item: listItem }">
                  <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
                    <span>{{ listItem.text }}</span>
                    <gl-badge class="gl-shrink-0">{{
                      managedByLabel(listItem.profile, rootGroupName)
                    }}</gl-badge>
                  </div>
                </template>
              </gl-collapsible-listbox>
              <span
                v-else
                :class="{ 'gl-italic': item.status === $options.SCAN_PROFILE_STATUS_MIXED }"
              >
                {{ profileText(item) }}
              </span>
              <template v-if="item.status === $options.SCAN_PROFILE_STATUS_MIXED">
                <gl-icon
                  :id="`${item.id}-profile`"
                  name="information-o"
                  class="gl-link gl-ml-2 gl-shrink-0"
                />
                <gl-popover :target="`${item.id}-profile`">
                  {{
                    __(
                      'The selected projects use different configuration profiles. Choosing a new profile will replace their existing ones.',
                    )
                  }}
                </gl-popover>
              </template>
              <template
                v-if="item.status === $options.SCAN_PROFILE_STATUS_APPLIED && item.description"
              >
                <gl-icon
                  :id="`${item.id}-profile`"
                  name="information-o"
                  class="gl-link gl-ml-2 gl-shrink-0"
                />
                <gl-popover :target="`${item.id}-profile`">
                  {{ item.description }}
                </gl-popover>
              </template>
            </div>
            <gl-badge
              v-if="showsManagedByBadge(item)"
              class="gl-mt-1 gl-self-start"
              data-testid="managed-by-badge"
            >
              {{ managedByLabel(item, rootGroupName) }}
            </gl-badge>
          </div>
        </template>

        <template #cell(actions)="{ item }">
          <div data-testid="actions-cell" class="gl-flex gl-flex-wrap gl-justify-end gl-gap-3">
            <gl-button-group v-if="item.status !== $options.SCAN_PROFILE_STATUS_APPLIED">
              <gl-button
                data-testid="apply-default-profile-button"
                variant="confirm"
                category="secondary"
                :disabled="!item.id"
                @click="$emit('attach-profile', item)"
              >
                {{ applyButtonLabel(item) }}
              </gl-button>
              <gl-button
                v-gl-tooltip
                data-testid="preview-default-profile-button"
                :title="previewButtonLabel(item)"
                :aria-label="previewButtonLabel(item)"
                variant="confirm"
                category="secondary"
                icon="eye"
                icon-only
                :disabled="!item.id"
                @click="$emit('preview-profile', item)"
              />
            </gl-button-group>
            <gl-button
              v-if="item.status !== $options.SCAN_PROFILE_STATUS_DISABLED"
              data-testid="disable-for-all-button"
              variant="danger"
              category="secondary"
              @click="$emit('detach-profile', item)"
            >
              {{ __('Disable for all') }}
            </gl-button>
          </div>
        </template>
      </gl-table-lite>
    </crud-component>
  </div>
</template>
