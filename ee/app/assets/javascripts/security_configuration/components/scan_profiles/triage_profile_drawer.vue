<script>
import { GlBadge, GlTab, GlTabs } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import ProfileListDrawer from './profile_list_drawer.vue';
import TriagePresetCapabilities from './triage_preset_capabilities.vue';
import { scanTypeName, managedByLabel } from './utils';

const FLASH_CONTAINER_CLASS = 'js-triage-profile-drawer-flash-container';
const STANDARD_TRIAGE_PRESET_NAME = 'Triage and Remediation (Standard)';

const i18n = {
  generalDetails: s__('ScanProfiles|General details'),
  description: s__('ScanProfiles|Description'),
  profileType: s__('ScanProfiles|Profile type'),
  managedBy: s__('ScanProfiles|Managed by'),
};

export default {
  name: 'TriageProfileDrawer',
  components: {
    CrudComponent,
    GlBadge,
    GlTab,
    GlTabs,
    ProfileListDrawer,
    TriagePresetCapabilities,
  },
  inject: ['groupFullPath'],
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    project: {
      type: Object,
      required: false,
      default: null,
    },
    presetId: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['close'],
  data() {
    return {
      allProfiles: [],
      selectedId: '',
      hasLoadError: false,
    };
  },
  apollo: {
    allProfiles: {
      query: groupAvailableSecurityScanProfilesQuery,
      skip() {
        return !this.open;
      },
      variables() {
        return { fullPath: this.groupFullPath, gitlabRecommended: true };
      },
      update(data) {
        return data?.group?.availableSecurityScanProfiles ?? [];
      },
      result({ data }) {
        if (!data) return;

        this.hasLoadError = false;
      },
      error(error) {
        this.hasLoadError = true;
        createAlert({
          message: s__('SecurityConfiguration|Failed to load triage and remediation profiles.'),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    presets() {
      return this.allProfiles.filter(
        ({ scanType }) => scanType === SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
      );
    },
    selectedPreset() {
      return (
        this.presets.find(({ id }) => id === this.selectedId) ??
        this.presets.find(({ id }) => id === this.presetId) ??
        this.presets.find(this.isRecommended) ??
        this.presets[0]
      );
    },
    isLoading() {
      return this.$apollo.queries.allProfiles.loading;
    },
    generalDetails() {
      return [
        { label: i18n.description, value: this.selectedPreset.description },
        { label: i18n.profileType, value: scanTypeName(this.selectedPreset.scanType) },
        { label: i18n.managedBy, value: managedByLabel(this.selectedPreset), isBadge: true },
      ];
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.selectedId = '';
      }
    },
  },
  methods: {
    isSelected(preset) {
      return preset.id === this.selectedPreset?.id;
    },
    isRecommended(preset) {
      return preset.name === STANDARD_TRIAGE_PRESET_NAME;
    },
    isApplied(preset) {
      return Boolean(this.project) && preset.id === this.presetId;
    },
  },
  FLASH_CONTAINER_CLASS,
  i18n,
};
</script>

<template>
  <profile-list-drawer
    :open="open"
    :title="s__('SecurityConfiguration|Select an Automated Triage and Remediation profile')"
    :loading="isLoading"
    :error="hasLoadError"
    data-testid="triage-profile-drawer"
    @close="$emit('close')"
  >
    <div :class="$options.FLASH_CONTAINER_CLASS" class="empty:gl-hidden"></div>

    <template #list>
      <ul class="gl-m-0 gl-list-none gl-p-0" data-testid="triage-profile-list">
        <li v-for="preset in presets" :key="preset.id" class="gl-mr-5">
          <button
            type="button"
            class="gl-w-full gl-cursor-pointer gl-rounded-base gl-border-0 gl-bg-transparent gl-px-4 gl-py-3 gl-text-left"
            :class="{ '!gl-bg-feedback-info': isSelected(preset) }"
            :aria-current="isSelected(preset) ? 'true' : null"
            data-testid="triage-profile-list-item"
            @click="selectedId = preset.id"
          >
            <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
              <span class="gl-font-bold gl-text-default">{{ preset.name }}</span>
              <gl-badge v-if="isApplied(preset)" variant="success" data-testid="applied-badge">
                {{ __('Applied') }}
              </gl-badge>
              <gl-badge
                v-else-if="isRecommended(preset)"
                variant="info"
                data-testid="recommended-badge"
              >
                {{ __('Recommended') }}
              </gl-badge>
            </span>
            <span class="gl-mt-1 gl-line-clamp-2 gl-text-sm gl-text-subtle">
              {{ preset.description }}
            </span>
          </button>
        </li>
      </ul>
    </template>

    <template #detail>
      <div v-if="selectedPreset" data-testid="triage-profile-detail">
        <div class="gl-mb-5 gl-flex gl-flex-wrap gl-items-center gl-gap-2">
          <h3 class="gl-heading-3 gl-mb-0">{{ selectedPreset.name }}</h3>
          <gl-badge
            v-if="isApplied(selectedPreset)"
            variant="success"
            data-testid="detail-applied-badge"
          >
            {{ __('Applied') }}
          </gl-badge>
          <gl-badge
            v-else-if="isRecommended(selectedPreset)"
            variant="info"
            data-testid="detail-recommended-badge"
          >
            {{ __('Recommended') }}
          </gl-badge>
        </div>
        <gl-tabs>
          <gl-tab :title="s__('SecurityConfiguration|Configuration')">
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
            <triage-preset-capabilities :triggers="selectedPreset.triggers" />
          </gl-tab>
        </gl-tabs>
      </div>
    </template>
  </profile-list-drawer>
</template>
