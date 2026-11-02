import { shallowMount } from '@vue/test-utils';
import { GlAlert, GlButton, GlSprintf } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import projectInfoQuery from 'ee_component/repository/queries/project_info.query.graphql';
import currentUserQuery from '~/graphql_shared/queries/current_user.query.graphql';
import LockDirectoryButton from 'ee_component/repository/components/lock_directory_button.vue';
import LockButton from 'ee_component/repository/components/header_area/lock_button.vue';
import {
  projectMock,
  getProjectMockWithOverrides,
  exactDirectoryLock,
  upstreamDirectoryLock,
  downstreamDirectoryLock,
  userMock,
} from 'ee_jest/repository/mock_data';

Vue.use(VueApollo);
jest.mock('~/alert');
jest.mock('~/lib/logger');

describe('LockDirectoryButton', () => {
  let wrapper;
  let fakeApollo;

  const mockRequestError = new Error('Request failed');

  const currentUserMockResolver = jest.fn().mockResolvedValue(userMock);
  const signedOutUserResolver = jest.fn().mockResolvedValue({ data: { currentUser: null } });
  const currentUserErrorResolver = jest.fn().mockRejectedValue(mockRequestError);

  const projectInfoQueryMockResolver = jest
    .fn()
    .mockResolvedValue({ data: { project: projectMock } });
  const projectInfoQueryErrorResolver = jest.fn().mockRejectedValue(mockRequestError);

  const createComponent = ({
    fileLocks = true,
    props = {},
    provide = {},
    projectInfoResolver = projectInfoQueryMockResolver,
    currentUserResolver = currentUserMockResolver,
  } = {}) => {
    fakeApollo = createMockApollo([
      [projectInfoQuery, projectInfoResolver],
      [currentUserQuery, currentUserResolver],
    ]);

    wrapper = shallowMount(LockDirectoryButton, {
      apolloProvider: fakeApollo,
      provide: {
        glLicensedFeatures: {
          fileLocks,
        },
        currentRef: 'main',
        ...provide,
      },
      propsData: {
        projectPath: 'group/project',
        path: 'test/component',
        ...props,
      },
      stubs: {
        GlAlert,
        GlSprintf,
        GlButton,
        LockButton: stubComponent(LockButton, {
          template: '<div><slot name="disclosure-alert"></slot><slot name="footer"></slot></div>',
        }),
      },
    });
  };

  const findLockButton = () => wrapper.findComponent(LockButton);
  const findRelatedLockAlert = () => wrapper.find('[data-testid="related-lock-alert"]');
  const findViewLockedPathButton = () => wrapper.find('[data-testid="view-locked-path-button"]');

  beforeEach(async () => {
    createComponent();
    await waitForPromises();
  });

  afterEach(() => {
    fakeApollo = null;
  });

  describe('lock button', () => {
    const createLockButtonComponent = ({
      pathLockNodesOverride = [],
      userPermissionsOverride = {},
      ...options
    } = {}) => {
      createComponent({
        projectInfoResolver: jest.fn().mockResolvedValue({
          data: {
            project: getProjectMockWithOverrides({
              pathLockNodesOverride,
              userPermissionsOverride,
            }),
          },
        }),
        ...options,
      });
      return waitForPromises();
    };

    it('renders the lock button component', async () => {
      await createLockButtonComponent();

      expect(findLockButton().exists()).toBe(true);
    });

    it('does not render the lock button when the fileLocks licensed feature is not available', async () => {
      await createLockButtonComponent({ fileLocks: false });

      expect(findLockButton().exists()).toBe(false);
    });

    it('does not render the lock button when the user is not signed in', async () => {
      await createLockButtonComponent({ currentUserResolver: signedOutUserResolver });

      expect(findLockButton().exists()).toBe(false);
    });

    it('passes unlocked state for a directory without locks', async () => {
      await createLockButtonComponent();

      expect(findLockButton().props()).toMatchObject({
        isLocked: false,
        lockUser: null,
        lockedAt: null,
        canDestroyLock: false,
        canCreateLock: true,
        projectPath: 'group/project',
        path: 'test/component',
        resourceType: 'directory',
      });
    });

    it('does not allow creating a lock when the user lacks permission', async () => {
      await createLockButtonComponent({ userPermissionsOverride: { createPathLock: false } });

      expect(findLockButton().props('canCreateLock')).toBe(false);
    });

    describe('when there is an exact lock', () => {
      it('passes the lock details and unlock permission without an alert', async () => {
        await createLockButtonComponent({ pathLockNodesOverride: [exactDirectoryLock] });

        expect(findLockButton().props()).toMatchObject({
          isLocked: true,
          lockUser: exactDirectoryLock.user,
          lockedAt: exactDirectoryLock.createdAt,
          canDestroyLock: true,
        });
        expect(findRelatedLockAlert().exists()).toBe(false);
        expect(findViewLockedPathButton().exists()).toBe(false);
      });

      it('does not allow unlocking when the user lacks permission', async () => {
        await createLockButtonComponent({
          pathLockNodesOverride: [
            { ...exactDirectoryLock, userPermissions: { destroyPathLock: false } },
          ],
        });

        expect(findLockButton().props('canDestroyLock')).toBe(false);
      });
    });

    describe('when there is an upstream lock', () => {
      it('shows the locked state without unlock permission and explains it in an alert', async () => {
        await createLockButtonComponent({ pathLockNodesOverride: [upstreamDirectoryLock] });

        expect(findLockButton().props()).toMatchObject({
          isLocked: true,
          lockUser: upstreamDirectoryLock.user,
          lockedAt: upstreamDirectoryLock.createdAt,
          canDestroyLock: false,
        });
        expect(findRelatedLockAlert().text()).toBe(
          'The parent directory "test" is locked. To unlock this directory, unlock "test".',
        );
      });

      it('renders a footer button linking to the locked directory', async () => {
        await createLockButtonComponent({ pathLockNodesOverride: [upstreamDirectoryLock] });

        expect(findViewLockedPathButton().text()).toBe('View lock');
        expect(findViewLockedPathButton().attributes('href')).toBe(
          '/group/project/-/tree/main/test',
        );
      });
    });

    describe('when there is a downstream lock', () => {
      it('shows the locked state without unlock permission and explains it in an alert', async () => {
        await createLockButtonComponent({ pathLockNodesOverride: [downstreamDirectoryLock] });

        expect(findLockButton().props()).toMatchObject({
          isLocked: true,
          lockUser: downstreamDirectoryLock.user,
          lockedAt: downstreamDirectoryLock.createdAt,
          canDestroyLock: false,
        });
        expect(findRelatedLockAlert().text()).toBe(
          'You cannot lock this directory because "test/component/icon" inside it is locked.',
        );
      });

      it('renders a footer button linking to the locked path', async () => {
        await createLockButtonComponent({ pathLockNodesOverride: [downstreamDirectoryLock] });

        expect(findViewLockedPathButton().text()).toBe('View lock');
        expect(findViewLockedPathButton().attributes('href')).toBe(
          '/group/project/-/tree/main/test/component/icon',
        );
      });

      it('falls back to the root ref in the href when the provided currentRef is null', async () => {
        await createLockButtonComponent({
          pathLockNodesOverride: [downstreamDirectoryLock],
          provide: { currentRef: null },
        });

        expect(findViewLockedPathButton().attributes('href')).toBe(
          '/group/project/-/tree/main/test/component/icon',
        );
      });

      it('escapes special characters in the locked path href', async () => {
        await createLockButtonComponent({
          pathLockNodesOverride: [{ ...downstreamDirectoryLock, path: 'test/component/c#-app' }],
        });

        expect(findViewLockedPathButton().attributes('href')).toBe(
          '/group/project/-/tree/main/test/component/c%23-app',
        );
      });
    });
  });

  describe('alert', () => {
    it('creates an alert with the correct message, when projectInfo query fails', async () => {
      createComponent({
        projectInfoResolver: projectInfoQueryErrorResolver,
      });
      await waitForPromises();
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred while fetching lock information, please try again.',
      });
    });

    it('creates an alert with the correct message, when currentUser query fails', async () => {
      createComponent({
        currentUserResolver: currentUserErrorResolver,
      });
      await waitForPromises();
      expect(createAlert).toHaveBeenCalledWith({
        message: 'An error occurred while fetching lock information, please try again.',
      });
    });
  });
});
