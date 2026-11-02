import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlDrawer, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ScanProfileDrawer from 'ee/security_configuration/components/scan_profiles/scan_profile_drawer.vue';
import ScanProfileList from 'ee/security_configuration/components/scan_profiles/scan_profile_list.vue';
import ScanProfileDetail from 'ee/security_configuration/components/scan_profiles/scan_profile_detail.vue';
import DeleteScanProfileConfirmationModal from 'ee/security_configuration/components/scan_profiles/delete_scan_profile_confirmation_modal.vue';
import ScanProfileEditForm from 'ee/security_configuration/components/scan_profiles/scan_profile_edit_form.vue';
import ProfileListDrawer from 'ee/security_configuration/components/scan_profiles/profile_list_drawer.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import securityScanProfileCreateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql';
import securityScanProfileDeleteMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_delete.mutation.graphql';
import securityScanProfileUpdateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql';
import {
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

Vue.use(VueApollo);

const mockAlertDismiss = jest.fn();
jest.mock('~/alert', () => ({
  createAlert: jest.fn().mockImplementation(() => ({
    dismiss: mockAlertDismiss,
  })),
}));

const GROUP_FULL_PATH = 'my-group';

describe('ScanProfileDrawer', () => {
  let wrapper;

  const buildProfile = (overrides = {}) => ({
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection (default)',
    description: 'The recommended profile',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
    gitlabRecommended: true,
    triggers: ['MERGE_REQUEST_PIPELINE'],
    triggerSettings: [
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: null,
        __typename: 'ScanProfileTriggerSetting',
      },
    ],
    projectCount: 0,
    __typename: 'ScanProfileType',
    ...overrides,
  });

  const recommendedProfile = buildProfile();
  const customProfile = buildProfile({
    id: 'gid://gitlab/Security::ScanProfile/2',
    name: 'A custom profile',
    description: 'One the group made',
    gitlabRecommended: false,
    projectCount: 2,
  });
  const sastProfile = buildProfile({
    id: 'gid://gitlab/Security::ScanProfile/3',
    name: 'SAST (default)',
    scanType: SCAN_PROFILE_TYPE_SAST,
  });

  const allPermissions = {
    createSecurityScanProfiles: true,
    updateSecurityScanProfiles: true,
    deleteSecurityScanProfiles: true,
    __typename: 'GroupPermissions',
  };

  const createResolver = (
    profiles = [recommendedProfile, customProfile, sastProfile],
    userPermissions = allPermissions,
  ) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          name: GROUP_FULL_PATH,
          userPermissions,
          availableSecurityScanProfiles: profiles,
          __typename: 'Group',
        },
      },
    });

  const createDeleteResolver = ({ id, errors = [] } = {}) =>
    jest.fn().mockResolvedValue({
      data: {
        securityScanProfileDelete: {
          clientMutationId: null,
          errors,
          deletedScanProfileId: id ?? null,
          __typename: 'SecurityScanProfileDeletePayload',
        },
      },
    });

  const createUpdateResolver = ({ profile, errors = [] } = {}) =>
    jest.fn().mockResolvedValue({
      data: {
        securityScanProfileUpdate: {
          clientMutationId: null,
          errors,
          scanProfile: profile
            ? {
                ...profile,
                triggerSettings: (profile.triggers ?? []).map((triggerType) => ({
                  triggerType,
                  configuration: null,
                  __typename: 'ScanProfileTriggerSetting',
                })),
              }
            : null,
          __typename: 'SecurityScanProfileUpdatePayload',
        },
      },
    });

  const createCreateResolver = ({ profile, errors = [] } = {}) =>
    jest.fn().mockResolvedValue({
      data: {
        securityScanProfileCreate: {
          clientMutationId: null,
          errors,
          scanProfile: profile
            ? {
                ...profile,
                triggerSettings: (profile.triggers ?? []).map((triggerType) => ({
                  triggerType,
                  configuration: null,
                  __typename: 'ScanProfileTriggerSetting',
                })),
              }
            : null,
          __typename: 'SecurityScanProfileCreatePayload',
        },
      },
    });

  const createComponent = ({
    props = {},
    resolver = createResolver(),
    deleteResolver = createDeleteResolver(),
    updateResolver = createUpdateResolver(),
    createProfileResolver = createCreateResolver(),
  } = {}) => {
    wrapper = shallowMountExtended(ScanProfileDrawer, {
      apolloProvider: createMockApollo([
        [groupAvailableSecurityScanProfilesQuery, resolver],
        [securityScanProfileDeleteMutation, deleteResolver],
        [securityScanProfileUpdateMutation, updateResolver],
        [securityScanProfileCreateMutation, createProfileResolver],
      ]),
      propsData: {
        open: true,
        scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
        ...props,
      },
      provide: {
        groupFullPath: GROUP_FULL_PATH,
        namespaceId: '1',
      },
      stubs: {
        ProfileListDrawer,
        GlDrawer: stubComponent(GlDrawer, {
          template: '<div><slot name="title" /><slot /></div>',
        }),
      },
      mocks: {
        $toast: { show: jest.fn() },
      },
    });
  };

  const findDrawer = () => wrapper.findComponent(GlDrawer);
  const findList = () => wrapper.findComponent(ScanProfileList);
  const findTitle = () => wrapper.find('h4');
  const findDetail = () => wrapper.findComponent(ScanProfileDetail);
  const findLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findDeleteModal = () => wrapper.findComponent(DeleteScanProfileConfirmationModal);
  const findEditForm = () => wrapper.findComponent(ScanProfileEditForm);

  describe('drawer', () => {
    it('is closed by default', () => {
      createComponent({ props: { open: false } });

      expect(findDrawer().props('open')).toBe(false);
    });

    it('is open when the open prop is set', () => {
      createComponent();

      expect(findDrawer().props('open')).toBe(true);
    });

    it('emits close when the drawer is dismissed', () => {
      createComponent();

      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    describe('when a delete confirmation is pending', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('delete');
        await waitForPromises();
      });

      it('swallows the drawer close so only the modal reacts to Esc', () => {
        findDrawer().vm.$emit('close');

        expect(wrapper.emitted('close')).toBeUndefined();
        expect(findDeleteModal().props('visible')).toBe(true);
      });

      it('clears the pending profile when the drawer is reopened', async () => {
        await wrapper.setProps({ open: false });
        await wrapper.setProps({ open: true });
        await waitForPromises();

        expect(findDeleteModal().props('visible')).toBe(false);
      });
    });

    describe('when the edit form is open', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();
      });

      it('returns to the read-only detail when the drawer emits close', async () => {
        findDrawer().vm.$emit('close');
        await waitForPromises();

        expect(wrapper.emitted('close')).toBeUndefined();
        expect(findEditForm().exists()).toBe(false);
        expect(findDetail().exists()).toBe(true);
      });

      it('exits edit mode when the drawer is reopened', async () => {
        await wrapper.setProps({ open: false });
        await wrapper.setProps({ open: true });
        await waitForPromises();

        expect(findEditForm().exists()).toBe(false);
      });
    });
  });

  describe('title', () => {
    it('names the scanner for a known scan type, in sentence case', () => {
      createComponent();

      expect(wrapper.text()).toContain('Manage secret detection profiles');
    });

    it('keeps the capitals in an acronym scanner name', () => {
      createComponent({ props: { scanType: SCAN_PROFILE_TYPE_SAST } });

      expect(wrapper.text()).toContain(
        'Manage static application security testing (SAST) profiles',
      );
    });

    it('falls back to a generic title for an unknown scan type', () => {
      createComponent({ props: { scanType: 'NOT_A_SCANNER' } });

      expect(wrapper.text()).toContain('Manage profiles');
    });
  });

  describe('fetching', () => {
    it('does not query while the drawer is closed', async () => {
      const resolver = createResolver();
      createComponent({ props: { open: false }, resolver });
      await waitForPromises();

      expect(resolver).not.toHaveBeenCalled();
    });

    it('queries the group when the drawer is open', async () => {
      const resolver = createResolver();
      createComponent({ resolver });
      await waitForPromises();

      expect(resolver).toHaveBeenCalledWith({ fullPath: GROUP_FULL_PATH });
    });

    it('renders a skeleton while loading', () => {
      createComponent();

      expect(findLoader().exists()).toBe(true);
      expect(findList().exists()).toBe(false);
    });
  });

  describe('the list', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it("passes only profiles of the drawer's scan type", () => {
      expect(findList().props('profiles')).toEqual([recommendedProfile, customProfile]);
    });

    it('selects the first profile by default', () => {
      expect(findList().props('selectedId')).toBe(recommendedProfile.id);
      expect(findDetail().props('profile')).toEqual(recommendedProfile);
    });

    it('swaps the detail pane when another profile is selected', async () => {
      findList().vm.$emit('select', customProfile.id);
      await waitForPromises();

      expect(findDetail().props('profile')).toEqual(customProfile);
    });
  });

  describe('permissions', () => {
    it('passes the queried permissions down', async () => {
      createComponent();
      await waitForPromises();

      expect(findList().props('canCreate')).toBe(true);
      expect(findDetail().props()).toMatchObject({
        canCreate: true,
        canUpdate: true,
        canDelete: true,
      });
    });

    it('passes false for withheld permissions', async () => {
      createComponent({
        resolver: createResolver(undefined, {
          ...allPermissions,
          createSecurityScanProfiles: false,
          deleteSecurityScanProfiles: false,
        }),
      });
      await waitForPromises();

      expect(findList().props('canCreate')).toBe(false);
      expect(findDetail().props()).toMatchObject({
        canCreate: false,
        canUpdate: true,
        canDelete: false,
      });
    });
  });

  describe('default selection', () => {
    it('takes the first profile the resolver returns', async () => {
      createComponent({ resolver: createResolver([customProfile, recommendedProfile]) });
      await waitForPromises();

      expect(findList().props('selectedId')).toBe(customProfile.id);
    });
  });

  describe('when the scan type changes', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      await wrapper.setProps({ scanType: SCAN_PROFILE_TYPE_SAST });
      await waitForPromises();
    });

    it('lists the profiles of the new scan type', () => {
      expect(findList().props('profiles')).toEqual([sastProfile]);
    });

    it('selects the first profile of the new scan type', () => {
      expect(findList().props('selectedId')).toBe(sastProfile.id);
      expect(findDetail().props('profile')).toEqual(sastProfile);
    });
  });

  describe('when the drawer is reopened', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findList().vm.$emit('select', customProfile.id);
      await waitForPromises();

      await wrapper.setProps({ open: false });
      await wrapper.setProps({ open: true });
      await waitForPromises();
    });

    it('goes back to the default selection', () => {
      expect(findList().props('selectedId')).toBe(recommendedProfile.id);
    });
  });

  describe('empty state', () => {
    it('is shown inside the list when no profile matches the scan type', async () => {
      createComponent({ resolver: createResolver([sastProfile]) });
      await waitForPromises();

      expect(findList().exists()).toBe(true);
      expect(findList().props('profiles')).toHaveLength(0);
    });

    it('can open create mode from the empty state', async () => {
      createComponent({ resolver: createResolver([sastProfile]) });
      await waitForPromises();

      findList().vm.$emit('create');
      await waitForPromises();

      expect(findEditForm().exists()).toBe(true);
    });
  });

  describe('when the query fails', () => {
    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException');
      createComponent({ resolver: jest.fn().mockRejectedValue(new Error()) });
      await waitForPromises();
    });

    it('reports the error to Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
    });

    it('alerts inside the drawer rather than behind it', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to load scan profiles.',
        containerSelector: '.js-scan-profile-drawer-flash-container',
      });
    });

    it('renders neither the list nor the detail pane behind the alert', () => {
      expect(findList().exists()).toBe(false);
      expect(findDetail().exists()).toBe(false);
    });
  });

  describe('deleting a profile', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findList().vm.$emit('select', customProfile.id);
      await waitForPromises();
    });

    it('hides the delete confirmation modal by default', () => {
      expect(findDeleteModal().props('visible')).toBe(false);
    });

    it('opens the modal with the profile name and project count when the detail pane requests deletion', async () => {
      findDetail().vm.$emit('delete');
      await waitForPromises();

      expect(findDeleteModal().props('visible')).toBe(true);
      expect(findDeleteModal().props('profileName')).toBe(customProfile.name);
      expect(findDeleteModal().props('projectCount')).toBe(customProfile.projectCount);
    });

    it('closes the modal without mutating when the user cancels', async () => {
      const deleteResolver = createDeleteResolver({ id: customProfile.id });
      createComponent({ deleteResolver });
      await waitForPromises();

      findList().vm.$emit('select', customProfile.id);
      await waitForPromises();
      findDetail().vm.$emit('delete');
      await waitForPromises();

      findDeleteModal().vm.$emit('cancel');
      await waitForPromises();

      expect(findDeleteModal().props('visible')).toBe(false);
      expect(deleteResolver).not.toHaveBeenCalled();
    });

    describe('on successful confirmation', () => {
      let resolver;
      let deleteResolver;

      beforeEach(async () => {
        resolver = createResolver();
        deleteResolver = createDeleteResolver({ id: customProfile.id });
        createComponent({ resolver, deleteResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('delete');
        await waitForPromises();

        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('calls the delete mutation with the profile id', () => {
        expect(deleteResolver).toHaveBeenCalledWith({ input: { id: customProfile.id } });
      });

      it('refetches the profile list', () => {
        // one for the initial load, one for the refetch
        expect(resolver).toHaveBeenCalledTimes(2);
      });

      it('closes the confirmation modal', () => {
        expect(findDeleteModal().props('visible')).toBe(false);
      });

      it('clears the selection when the deleted profile was selected', () => {
        expect(findList().props('selectedId')).toBe(recommendedProfile.id);
      });

      it('does not alert an error', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('shows a success toast with the deleted profile name', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Deleted “A custom profile”');
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const deleteResolver = createDeleteResolver({ errors: ['Nope'] });
        createComponent({ deleteResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('delete');
        await waitForPromises();

        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('alerts inside the drawer with the profile name', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Failed to delete “A custom profile”.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation network call fails', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const deleteResolver = jest.fn().mockRejectedValue(new Error('network'));
        createComponent({ deleteResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('delete');
        await waitForPromises();

        findDeleteModal().vm.$emit('confirm');
        await waitForPromises();
      });

      it('alerts inside the drawer with the profile name', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Failed to delete “A custom profile”.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('editing a profile', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findList().vm.$emit('select', customProfile.id);
      await waitForPromises();
    });

    it('does not show the edit form by default', () => {
      expect(findEditForm().exists()).toBe(false);
      expect(findDetail().exists()).toBe(true);
    });

    it('swaps the detail pane for the edit form when the detail requests edit', async () => {
      findDetail().vm.$emit('edit');
      await waitForPromises();

      expect(findDetail().exists()).toBe(false);
      expect(findEditForm().exists()).toBe(true);
      expect(findEditForm().props('profile')).toEqual(customProfile);
    });

    it('hides the profile list and switches the title while editing', async () => {
      expect(findList().exists()).toBe(true);
      expect(findTitle().text()).toBe('Manage secret detection profiles');

      findDetail().vm.$emit('edit');
      await waitForPromises();

      expect(findList().exists()).toBe(false);
      expect(findTitle().text()).toBe('Edit secret detection profile');
    });

    it('returns to the detail pane when the form emits cancel', async () => {
      findDetail().vm.$emit('edit');
      await waitForPromises();

      findEditForm().vm.$emit('cancel');
      await waitForPromises();

      expect(findDetail().exists()).toBe(true);
      expect(findEditForm().exists()).toBe(false);
    });

    describe('on save with only name and description changes', () => {
      let updateResolver;

      beforeEach(async () => {
        updateResolver = createUpdateResolver({ profile: customProfile });
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile',
          description: 'New description',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('sends only id, name, and description (no triggers)', () => {
        expect(updateResolver).toHaveBeenCalledWith({
          input: {
            id: customProfile.id,
            name: 'Renamed profile',
            description: 'New description',
          },
        });
      });

      it('exits edit mode and refetches the profile list', () => {
        expect(findEditForm().exists()).toBe(false);
        expect(findDetail().exists()).toBe(true);
      });

      it('shows a success toast with the new profile name', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Changes to “Renamed profile” saved');
      });
    });

    describe('on save with trigger changes', () => {
      let updateResolver;

      beforeEach(async () => {
        updateResolver = createUpdateResolver({ profile: customProfile });
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: customProfile.name,
          description: customProfile.description,
          enabledTriggers: ['DEFAULT_BRANCH_PIPELINE'],
          triggerConfigurations: {},
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('includes the mapped triggers with stripDefaults false', () => {
        expect(updateResolver).toHaveBeenCalledWith({
          input: {
            id: customProfile.id,
            name: customProfile.name,
            description: customProfile.description,
            stripDefaults: false,
            triggers: [{ triggerType: 'DEFAULT_BRANCH_PIPELINE' }],
          },
        });
      });
    });

    describe('on save with trigger changes and existing triggerConfigurations', () => {
      it('preserves existing trigger configurations', async () => {
        const updateResolver = createUpdateResolver({ profile: customProfile });
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: customProfile.name,
          description: customProfile.description,
          enabledTriggers: ['DEFAULT_BRANCH_PIPELINE'],
          triggerConfigurations: { DEFAULT_BRANCH_PIPELINE: { historicScan: true } },
          triggersChanged: true,
        });
        await waitForPromises();

        expect(updateResolver).toHaveBeenCalledWith({
          input: {
            id: customProfile.id,
            name: customProfile.name,
            description: customProfile.description,
            stripDefaults: false,
            triggers: [
              {
                triggerType: 'DEFAULT_BRANCH_PIPELINE',
                configuration: { secretDetection: { historicScan: true } },
              },
            ],
          },
        });
      });
    });

    describe('when the update mutation returns errors', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const updateResolver = createUpdateResolver({ errors: ['Nope'] });
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile',
          description: '',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('alerts inside the drawer with the server error', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Nope',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('does not report to Sentry', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('keeps the edit form open', () => {
        expect(findEditForm().exists()).toBe(true);
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });

    describe('when a failed attempt is retried and succeeds', () => {
      beforeEach(async () => {
        const updateResolver = jest
          .fn()
          .mockResolvedValueOnce({
            data: {
              securityScanProfileUpdate: {
                clientMutationId: null,
                errors: ['Nope'],
                scanProfile: null,
                __typename: 'SecurityScanProfileUpdatePayload',
              },
            },
          })
          .mockImplementation(createUpdateResolver({ profile: customProfile }));
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile',
          description: '',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile again',
          description: '',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('dismisses the earlier error alert', () => {
        expect(mockAlertDismiss).toHaveBeenCalledTimes(1);
      });

      it('shows the success toast', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith(
          'Changes to “Renamed profile again” saved',
        );
      });
    });

    describe('when the update mutation throws unexpectedly', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const updateResolver = jest.fn().mockRejectedValue(new Error('network error'));
        createComponent({ updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile',
          description: '',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('alerts inside the drawer with the profile name', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Failed to update “Renamed profile”.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });
    });

    describe('when the update mutation succeeds but the refetch fails', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const updateResolver = createUpdateResolver({ profile: customProfile });
        const resolver = jest
          .fn()
          .mockResolvedValueOnce({
            data: {
              group: {
                id: 'gid://gitlab/Group/1',
                name: GROUP_FULL_PATH,
                userPermissions: allPermissions,
                availableSecurityScanProfiles: [recommendedProfile, customProfile, sastProfile],
                __typename: 'Group',
              },
            },
          })
          .mockRejectedValueOnce(new Error('network error'));
        createComponent({ resolver, updateResolver });
        await waitForPromises();

        findList().vm.$emit('select', customProfile.id);
        await waitForPromises();
        findDetail().vm.$emit('edit');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          profileId: customProfile.id,
          scanType: customProfile.scanType,
          name: 'Renamed profile',
          description: '',
          enabledTriggers: customProfile.triggers,
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('alerts that the changes were saved but the list could not refresh', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message:
            'Changes to “Renamed profile” were saved, but the list could not be refreshed. Please refresh the page.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('creating a profile', () => {
    const newProfile = buildProfile({
      id: 'gid://gitlab/Security::ScanProfile/99',
      name: 'Brand new profile',
      description: 'Fresh',
      gitlabRecommended: false,
    });

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('does not show the edit form by default', () => {
      expect(findEditForm().exists()).toBe(false);
    });

    it('swaps the list for the edit form with an empty profile when the list requests create', async () => {
      findList().vm.$emit('create');
      await waitForPromises();

      expect(findList().exists()).toBe(false);
      expect(findEditForm().exists()).toBe(true);
      expect(findEditForm().props('profile')).toMatchObject({
        id: '',
        name: '',
        description: '',
        scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
        gitlabRecommended: false,
        triggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE', 'GIT_PUSH_EVENT'],
      });
    });

    it('shrinks the drawer and switches the title while creating', async () => {
      expect(findTitle().text()).toBe('Manage secret detection profiles');
      expect(findDrawer().classes()).not.toContain('!gl-max-w-3xl');

      findList().vm.$emit('create');
      await waitForPromises();

      expect(findTitle().text()).toBe('Create secret detection profile');
      expect(findDrawer().classes()).toContain('!gl-max-w-3xl');
    });

    it('resets isCreating when the drawer reopens', async () => {
      findList().vm.$emit('create');
      await waitForPromises();
      expect(findEditForm().exists()).toBe(true);

      wrapper.setProps({ open: false });
      await waitForPromises();
      wrapper.setProps({ open: true });
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
      expect(findList().exists()).toBe(true);
    });

    it('resets isCreating when the scan type changes', async () => {
      findList().vm.$emit('create');
      await waitForPromises();
      expect(findEditForm().exists()).toBe(true);

      wrapper.setProps({ scanType: SCAN_PROFILE_TYPE_SAST });
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
      expect(findList().exists()).toBe(true);
    });

    it('exits create mode when the form emits cancel', async () => {
      findList().vm.$emit('create');
      await waitForPromises();

      findEditForm().vm.$emit('cancel');
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
      expect(findList().exists()).toBe(true);
    });

    it('exits create mode when the drawer emits close (X or Esc)', async () => {
      findList().vm.$emit('create');
      await waitForPromises();

      findDrawer().vm.$emit('close');
      await waitForPromises();

      expect(wrapper.emitted('close')).toBeUndefined();
      expect(findEditForm().exists()).toBe(false);
    });

    describe('on save success', () => {
      let createProfileResolver;
      let resolver;

      beforeEach(async () => {
        createProfileResolver = createCreateResolver({ profile: newProfile });
        resolver = jest
          .fn()
          .mockResolvedValueOnce({
            data: {
              group: {
                id: 'gid://gitlab/Group/1',
                name: GROUP_FULL_PATH,
                userPermissions: allPermissions,
                availableSecurityScanProfiles: [recommendedProfile, customProfile, sastProfile],
                __typename: 'Group',
              },
            },
          })
          .mockResolvedValueOnce({
            data: {
              group: {
                id: 'gid://gitlab/Group/1',
                name: GROUP_FULL_PATH,
                userPermissions: allPermissions,
                availableSecurityScanProfiles: [
                  recommendedProfile,
                  customProfile,
                  sastProfile,
                  newProfile,
                ],
                __typename: 'Group',
              },
            },
          });
        createComponent({ resolver, createProfileResolver });
        await waitForPromises();

        findList().vm.$emit('create');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Brand new profile',
          description: 'Fresh',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('calls the create mutation with namespaceId, scan type, fields and triggers', () => {
        expect(createProfileResolver).toHaveBeenCalledWith({
          input: {
            namespaceId: 'gid://gitlab/Namespace/1',
            scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
            name: 'Brand new profile',
            description: 'Fresh',
            stripDefaults: false,
            triggers: [{ triggerType: 'MERGE_REQUEST_PIPELINE' }],
          },
        });
      });

      it('exits create mode', () => {
        expect(findEditForm().exists()).toBe(false);
      });

      it('refetches the profile list', () => {
        expect(resolver).toHaveBeenCalledTimes(2);
      });

      it('auto-selects the newly created profile', () => {
        expect(findList().props('selectedId')).toBe(newProfile.id);
        expect(findDetail().props('profile')).toMatchObject({
          id: newProfile.id,
          name: newProfile.name,
        });
      });

      it('shows a success toast naming the new profile', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Created “Brand new profile”');
      });
    });

    describe('when the create mutation returns errors', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const createProfileResolver = createCreateResolver({ errors: ['Name taken'] });
        createComponent({ createProfileResolver });
        await waitForPromises();

        findList().vm.$emit('create');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Brand new profile',
          description: '',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('alerts inside the drawer with the server error', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Name taken',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('does not report to Sentry', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('keeps the form open', () => {
        expect(findEditForm().exists()).toBe(true);
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });

    describe('when a failed attempt is retried and succeeds', () => {
      beforeEach(async () => {
        const createProfileResolver = jest
          .fn()
          .mockResolvedValueOnce({
            data: {
              securityScanProfileCreate: {
                clientMutationId: null,
                errors: ['Name taken'],
                scanProfile: null,
                __typename: 'SecurityScanProfileCreatePayload',
              },
            },
          })
          .mockImplementation(createCreateResolver({ profile: newProfile }));
        createComponent({ createProfileResolver });
        await waitForPromises();

        findList().vm.$emit('create');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Brand new profile',
          description: '',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Renamed brand new profile',
          description: '',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('dismisses the earlier error alert', () => {
        expect(mockAlertDismiss).toHaveBeenCalledTimes(1);
      });

      it('shows the success toast', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Created “Renamed brand new profile”');
      });
    });

    describe('when the mutation throws unexpectedly', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const createProfileResolver = jest.fn().mockRejectedValue(new Error('network error'));
        createComponent({ createProfileResolver });
        await waitForPromises();

        findList().vm.$emit('create');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Brand new profile',
          description: '',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('alerts inside the drawer with the profile name', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Failed to create “Brand new profile”.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });
    });

    describe('when the create mutation succeeds but the refetch fails', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        const createProfileResolver = createCreateResolver({ profile: newProfile });
        const resolver = jest
          .fn()
          .mockResolvedValueOnce({
            data: {
              group: {
                id: 'gid://gitlab/Group/1',
                name: GROUP_FULL_PATH,
                userPermissions: allPermissions,
                availableSecurityScanProfiles: [recommendedProfile, customProfile, sastProfile],
                __typename: 'Group',
              },
            },
          })
          .mockRejectedValueOnce(new Error('network error'));
        createComponent({ resolver, createProfileResolver });
        await waitForPromises();

        findList().vm.$emit('create');
        await waitForPromises();

        findEditForm().vm.$emit('save', {
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'Brand new profile',
          description: 'Fresh',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: true,
        });
        await waitForPromises();
      });

      it('alerts that the profile was created but the list could not refresh', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message:
            '“Brand new profile” was created, but the list could not be refreshed. Please refresh the page.',
          containerSelector: '.js-scan-profile-drawer-flash-container',
        });
      });

      it('reports to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('does not show a success toast', () => {
        expect(wrapper.vm.$toast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('duplicating a profile', () => {
    const selectProfile = async (id) => {
      findList().vm.$emit('select', id);
      await waitForPromises();
    };

    const openDuplicate = async (id) => {
      await selectProfile(id);
      findDetail().vm.$emit('duplicate');
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('swaps the list for the form pre-filled from the source profile', async () => {
      await openDuplicate(customProfile.id);

      expect(findList().exists()).toBe(false);
      expect(findEditForm().props('profile')).toEqual({
        id: '',
        name: 'A custom profile (copy)',
        description: 'One the group made',
        scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
        gitlabRecommended: false,
        triggers: ['MERGE_REQUEST_PIPELINE'],
        triggerSettings: customProfile.triggerSettings,
      });
    });

    it('duplicates a GitLab-managed profile as a custom one', async () => {
      await openDuplicate(recommendedProfile.id);

      expect(findEditForm().props('profile')).toMatchObject({
        name: 'Secret Detection (default) (copy)',
        gitlabRecommended: false,
      });
    });

    describe('when the default copy name is already taken', () => {
      beforeEach(async () => {
        createComponent({
          resolver: createResolver([
            customProfile,
            buildProfile({
              id: 'gid://gitlab/Security::ScanProfile/4',
              name: 'A custom profile (copy)',
              gitlabRecommended: false,
            }),
          ]),
        });
        await waitForPromises();
      });

      it('numbers the copy', async () => {
        await openDuplicate(customProfile.id);

        expect(findEditForm().props('profile').name).toBe('A custom profile (copy 2)');
      });
    });

    it('shrinks the drawer and switches the title while duplicating', async () => {
      expect(findDrawer().classes()).not.toContain('!gl-max-w-3xl');

      await openDuplicate(customProfile.id);

      expect(findTitle().text()).toBe('Duplicate secret detection profile');
      expect(findDrawer().classes()).toContain('!gl-max-w-3xl');
    });

    it('returns to the read-only detail when the form emits cancel', async () => {
      await openDuplicate(customProfile.id);

      findEditForm().vm.$emit('cancel');
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
      expect(findDetail().exists()).toBe(true);
    });

    it('returns to the read-only detail when the drawer emits close (X or Esc)', async () => {
      await openDuplicate(customProfile.id);

      findDrawer().vm.$emit('close');
      await waitForPromises();

      expect(wrapper.emitted('close')).toBeUndefined();
      expect(findEditForm().exists()).toBe(false);
    });

    it('exits duplicate mode when the drawer is reopened', async () => {
      await openDuplicate(customProfile.id);

      await wrapper.setProps({ open: false });
      await wrapper.setProps({ open: true });
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
    });

    it('exits duplicate mode when the scan type changes', async () => {
      await openDuplicate(customProfile.id);

      await wrapper.setProps({ scanType: SCAN_PROFILE_TYPE_SAST });
      await waitForPromises();

      expect(findEditForm().exists()).toBe(false);
    });

    describe('on save', () => {
      const duplicatedProfile = buildProfile({
        id: 'gid://gitlab/Security::ScanProfile/99',
        name: 'A custom profile (copy)',
        description: 'One the group made',
        gitlabRecommended: false,
      });

      let createProfileResolver;
      let updateResolver;

      beforeEach(async () => {
        createProfileResolver = createCreateResolver({ profile: duplicatedProfile });
        updateResolver = createUpdateResolver();
        createComponent({ createProfileResolver, updateResolver });
        await waitForPromises();

        await openDuplicate(customProfile.id);

        findEditForm().vm.$emit('save', {
          profileId: '',
          scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
          name: 'A custom profile (copy)',
          description: 'One the group made',
          enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
          triggersChanged: false,
        });
        await waitForPromises();
      });

      it('calls the create mutation rather than the update one', () => {
        expect(updateResolver).not.toHaveBeenCalled();
        expect(createProfileResolver).toHaveBeenCalledWith({
          input: {
            namespaceId: 'gid://gitlab/Namespace/1',
            scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
            name: 'A custom profile (copy)',
            description: 'One the group made',
            stripDefaults: false,
            triggers: [{ triggerType: 'MERGE_REQUEST_PIPELINE' }],
          },
        });
      });

      it('exits duplicate mode', () => {
        expect(findEditForm().exists()).toBe(false);
        expect(findList().exists()).toBe(true);
      });

      it('shows a success toast naming the new profile', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Created “A custom profile (copy)”');
      });
    });
  });
});
