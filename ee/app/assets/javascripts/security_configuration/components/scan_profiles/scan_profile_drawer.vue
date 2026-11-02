<script>
import { GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import { SCAN_PROFILE_CATEGORIES } from '~/security_configuration/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_NAMESPACE } from '~/graphql_shared/constants';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import securityScanProfileCreateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql';
import securityScanProfileDeleteMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_delete.mutation.graphql';
import securityScanProfileUpdateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql';
import {
  mapScanProfileVariables,
  buildScanProfileCreateInput,
} from 'ee/security_configuration/graphql/scan_profiles/map_scan_profile_variables';
import DeleteScanProfileConfirmationModal from './delete_scan_profile_confirmation_modal.vue';
import ScanProfileList from './scan_profile_list.vue';
import ScanProfileDetail from './scan_profile_detail.vue';
import ScanProfileEditForm from './scan_profile_edit_form.vue';
import ProfileListDrawer from './profile_list_drawer.vue';
import { allowedTriggersFor, duplicateProfileName } from './utils';

const FLASH_CONTAINER_CLASS = 'js-scan-profile-drawer-flash-container';

const i18n = {
  manageProfiles: s__('SecurityConfiguration|Manage profiles'),
  manageScannerProfiles: s__('SecurityConfiguration|Manage %{scannerName} profiles'),
  editProfile: s__('SecurityConfiguration|Edit profile'),
  editScannerProfile: s__('SecurityConfiguration|Edit %{scannerName} profile'),
  createProfile: s__('SecurityConfiguration|Create profile'),
  createScannerProfile: s__('SecurityConfiguration|Create %{scannerName} profile'),
  duplicateProfile: s__('SecurityConfiguration|Duplicate profile'),
  duplicateScannerProfile: s__('SecurityConfiguration|Duplicate %{scannerName} profile'),
  loadError: s__('SecurityConfiguration|Failed to load scan profiles.'),
  deleteError: s__('SecurityConfiguration|Failed to delete “%{profileName}”.'),
  deleteSuccess: s__('ScanProfiles|Deleted “%{profileName}”'),
  updateError: s__('SecurityConfiguration|Failed to update “%{profileName}”.'),
  updateRefetchError: s__(
    'SecurityConfiguration|Changes to “%{profileName}” were saved, but the list could not be refreshed. Please refresh the page.',
  ),
  updateSuccess: s__('ScanProfiles|Changes to “%{profileName}” saved'),
  createError: s__('SecurityConfiguration|Failed to create “%{profileName}”.'),
  createRefetchError: s__(
    'SecurityConfiguration|“%{profileName}” was created, but the list could not be refreshed. Please refresh the page.',
  ),
  createSuccess: s__('ScanProfiles|Created “%{profileName}”'),
};

export default {
  name: 'ScanProfileDrawer',
  components: {
    DeleteScanProfileConfirmationModal,
    ScanProfileList,
    ScanProfileDetail,
    ProfileListDrawer,
    ScanProfileEditForm,
  },
  mixins: [GlToastMixin],
  inject: ['groupFullPath', 'namespaceId'],
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    scanType: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['close'],
  data() {
    return {
      allProfiles: [],
      userPermissions: {},
      selectedId: '',
      alert: null,
      loading: 0,
      hasLoadError: false,
      pendingDeletionProfile: null,
      isDeleting: false,
      editingProfileId: '',
      duplicatingProfileId: '',
      isCreating: false,
      isSaving: false,
    };
  },
  apollo: {
    allProfiles: {
      query: groupAvailableSecurityScanProfilesQuery,
      skip() {
        return !this.open;
      },
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update(data) {
        return data?.group?.availableSecurityScanProfiles ?? [];
      },
      loadingKey: 'loading',
      result({ data }) {
        if (!data) return;

        this.hasLoadError = false;
        this.userPermissions = data.group?.userPermissions ?? {};
        this.selectDefaultProfile();
      },
      error(error) {
        this.hasLoadError = true;
        createAlert({
          message: i18n.loadError,
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    graphqlNamespaceId() {
      return convertToGraphQLId(TYPENAME_NAMESPACE, this.namespaceId);
    },
    title() {
      const displayName = SCAN_PROFILE_CATEGORIES[this.scanType]?.displayName;
      let scannerTemplate = i18n.manageScannerProfiles;
      let genericTemplate = i18n.manageProfiles;
      if (this.isCreating) {
        scannerTemplate = i18n.createScannerProfile;
        genericTemplate = i18n.createProfile;
      } else if (this.isDuplicating) {
        scannerTemplate = i18n.duplicateScannerProfile;
        genericTemplate = i18n.duplicateProfile;
      } else if (this.isEditing) {
        scannerTemplate = i18n.editScannerProfile;
        genericTemplate = i18n.editProfile;
      }

      if (!displayName) {
        return genericTemplate;
      }

      // Only the leading letter is lowered, so acronyms like SAST keep their capitals.
      const scannerName = displayName.charAt(0).toLowerCase() + displayName.slice(1);

      return sprintf(scannerTemplate, { scannerName });
    },
    profiles() {
      return this.allProfiles.filter(({ scanType }) => scanType === this.scanType);
    },
    selectedProfile() {
      return this.profiles.find(({ id }) => id === this.selectedId);
    },
    isEditing() {
      return Boolean(this.editingProfileId) && this.editingProfileId === this.selectedId;
    },
    isDuplicating() {
      return Boolean(this.duplicatingProfileId) && this.duplicatingProfileId === this.selectedId;
    },
    isFormOpen() {
      return this.isCreating || this.isEditing || this.isDuplicating;
    },
    formProfile() {
      if (this.isCreating) {
        return {
          id: '',
          name: '',
          description: '',
          scanType: this.scanType,
          gitlabRecommended: false,
          triggers: allowedTriggersFor(this.scanType),
        };
      }
      if (this.isDuplicating) {
        const { name, description, scanType, triggers, triggerSettings } = this.selectedProfile;
        return {
          // No id, so the form submits through create rather than update.
          id: '',
          name: duplicateProfileName(
            name,
            this.profiles.map((profile) => profile.name),
          ),
          description,
          scanType,
          gitlabRecommended: false,
          triggers,
          triggerSettings,
        };
      }
      return this.selectedProfile;
    },
    canCreate() {
      return Boolean(this.userPermissions.createSecurityScanProfiles);
    },
    canUpdate() {
      return Boolean(this.userPermissions.updateSecurityScanProfiles);
    },
    canDelete() {
      return Boolean(this.userPermissions.deleteSecurityScanProfiles);
    },
    isLoading() {
      return this.loading > 0;
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.selectedId = '';
        this.pendingDeletionProfile = null;
        this.editingProfileId = '';
        this.duplicatingProfileId = '';
        this.isCreating = false;
      }
    },
    scanType() {
      this.selectedId = '';
      this.editingProfileId = '';
      this.duplicatingProfileId = '';
      this.isCreating = false;
      this.selectDefaultProfile();
    },
  },
  methods: {
    selectDefaultProfile() {
      if (this.selectedProfile) return;

      this.selectedId = this.profiles[0]?.id ?? '';
    },
    handleDrawerClose() {
      // GlDrawer and GlModal both handle Esc, so when the delete modal is open Esc reaches both.
      // Swallow the drawer close while the modal is pending so only the modal closes.
      // While a form is open, dismissing the drawer (X button or Esc) returns to the read-only
      // list rather than closing the whole drawer.
      if (this.pendingDeletionProfile) return;
      if (this.isCreating) {
        this.cancelCreate();
        return;
      }
      if (this.duplicatingProfileId) {
        this.cancelDuplicate();
        return;
      }
      if (this.editingProfileId) {
        this.cancelEdit();
        return;
      }

      this.$emit('close');
    },
    openEdit(profile) {
      this.editingProfileId = profile.id;
    },
    cancelEdit() {
      if (this.isSaving) return;

      this.editingProfileId = '';
    },
    openCreate() {
      this.isCreating = true;
    },
    cancelCreate() {
      if (this.isSaving) return;

      this.isCreating = false;
    },
    openDuplicate(profile) {
      this.duplicatingProfileId = profile.id;
    },
    cancelDuplicate() {
      if (this.isSaving) return;

      this.duplicatingProfileId = '';
    },
    async saveCreate({ scanType, name, description, enabledTriggers, triggerConfigurations }) {
      if (this.isSaving) return;

      this.alert?.dismiss();
      this.isSaving = true;
      const input = buildScanProfileCreateInput({
        namespaceId: this.graphqlNamespaceId,
        scanType,
        name,
        description,
        enabledTriggers,
        triggerConfigurations,
        stripDefaults: false,
      });

      try {
        const { data } = await this.$apollo.mutate({
          mutation: securityScanProfileCreateMutation,
          variables: { input },
        });

        const errors = data?.securityScanProfileCreate?.errors ?? [];
        if (errors.length) {
          this.alert = createAlert({
            message: errors.join(' '),
            containerSelector: `.${FLASH_CONTAINER_CLASS}`,
          });
          return;
        }

        const newProfileId = data?.securityScanProfileCreate?.scanProfile?.id ?? '';
        try {
          // Refetch first so the drawer stays at its create size while the skeleton is on
          // screen; only widen the drawer once the list is ready.
          await this.$apollo.queries.allProfiles.refetch();
          this.isCreating = false;
          this.duplicatingProfileId = '';
          if (newProfileId) {
            this.selectedId = newProfileId;
          }
          this.$toast.show(sprintf(i18n.createSuccess, { profileName: name }));
        } catch (refetchError) {
          this.alert = createAlert({
            message: sprintf(i18n.createRefetchError, { profileName: name }),
            containerSelector: `.${FLASH_CONTAINER_CLASS}`,
          });
          Sentry.captureException(refetchError);
        }
      } catch (error) {
        this.alert = createAlert({
          message: sprintf(i18n.createError, { profileName: name }),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
    handleFormSave(payload) {
      if (this.isCreating || this.isDuplicating) {
        return this.saveCreate(payload);
      }
      return this.saveEdit(payload);
    },
    handleFormCancel() {
      if (this.isCreating) {
        this.cancelCreate();
      } else if (this.isDuplicating) {
        this.cancelDuplicate();
      } else {
        this.cancelEdit();
      }
    },
    async saveEdit({
      profileId,
      scanType,
      name,
      description,
      enabledTriggers,
      triggerConfigurations,
      triggersChanged,
    }) {
      if (this.isSaving) return;

      this.alert?.dismiss();
      this.isSaving = true;
      const input = { id: profileId, name, description };
      if (triggersChanged) {
        input.stripDefaults = false;
        input.triggers = mapScanProfileVariables({
          scanType,
          enabledTriggers,
          triggerConfigurations,
        });
      }

      try {
        const { data } = await this.$apollo.mutate({
          mutation: securityScanProfileUpdateMutation,
          variables: { input },
        });

        const errors = data?.securityScanProfileUpdate?.errors ?? [];
        if (errors.length) {
          this.alert = createAlert({
            message: errors.join(' '),
            containerSelector: `.${FLASH_CONTAINER_CLASS}`,
          });
          return;
        }

        try {
          // Refetch first so the drawer stays at its edit size while the skeleton
          // is on screen; only widen the drawer once the list is ready.
          await this.$apollo.queries.allProfiles.refetch();
          this.editingProfileId = '';
          this.$toast.show(sprintf(i18n.updateSuccess, { profileName: name }));
        } catch (refetchError) {
          this.alert = createAlert({
            message: sprintf(i18n.updateRefetchError, { profileName: name }),
            containerSelector: `.${FLASH_CONTAINER_CLASS}`,
          });
          Sentry.captureException(refetchError);
        }
      } catch (error) {
        this.alert = createAlert({
          message: sprintf(i18n.updateError, { profileName: name }),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      } finally {
        this.isSaving = false;
      }
    },
    openDeleteConfirmation(profile) {
      this.pendingDeletionProfile = profile;
    },
    cancelDeleteConfirmation() {
      if (this.isDeleting) return;

      this.pendingDeletionProfile = null;
    },
    async confirmDeleteProfile() {
      if (!this.pendingDeletionProfile || this.isDeleting) return;

      const profileToDelete = this.pendingDeletionProfile;
      this.isDeleting = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: securityScanProfileDeleteMutation,
          variables: { input: { id: profileToDelete.id } },
        });

        const errors = data?.securityScanProfileDelete?.errors ?? [];
        if (errors.length) {
          throw new Error(errors.join(', '));
        }

        this.pendingDeletionProfile = null;
        if (this.selectedId === profileToDelete.id) {
          this.selectedId = '';
        }
        await this.$apollo.queries.allProfiles.refetch();
        this.$toast.show(sprintf(i18n.deleteSuccess, { profileName: profileToDelete.name }));
      } catch (error) {
        createAlert({
          message: sprintf(i18n.deleteError, { profileName: profileToDelete.name }),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      } finally {
        this.isDeleting = false;
      }
    },
  },
  FLASH_CONTAINER_CLASS,
  i18n,
};
</script>

<template>
  <profile-list-drawer
    :open="open"
    :title="title"
    :narrow="isFormOpen"
    :loading="isLoading"
    :error="hasLoadError"
    :show-list="!isFormOpen"
    data-testid="scan-profile-drawer"
    @close="handleDrawerClose"
  >
    <div :class="$options.FLASH_CONTAINER_CLASS" class="empty:gl-hidden"></div>

    <template #list>
      <scan-profile-list
        :profiles="profiles"
        :selected-id="selectedId"
        :can-create="canCreate"
        @select="selectedId = $event"
        @create="openCreate"
      />
    </template>

    <template #detail>
      <scan-profile-edit-form
        v-if="formProfile && isFormOpen"
        :profile="formProfile"
        :is-saving="isSaving"
        @save="handleFormSave"
        @cancel="handleFormCancel"
      />
      <scan-profile-detail
        v-else-if="selectedProfile"
        :profile="selectedProfile"
        :can-create="canCreate"
        :can-update="canUpdate"
        :can-delete="canDelete"
        @edit="openEdit(selectedProfile)"
        @duplicate="openDuplicate(selectedProfile)"
        @delete="openDeleteConfirmation(selectedProfile)"
      />
    </template>

    <delete-scan-profile-confirmation-modal
      :visible="Boolean(pendingDeletionProfile)"
      :profile-name="pendingDeletionProfile ? pendingDeletionProfile.name : ''"
      :project-count="pendingDeletionProfile ? pendingDeletionProfile.projectCount : 0"
      @confirm="confirmDeleteProfile"
      @cancel="cancelDeleteConfirmation"
    />
  </profile-list-drawer>
</template>
