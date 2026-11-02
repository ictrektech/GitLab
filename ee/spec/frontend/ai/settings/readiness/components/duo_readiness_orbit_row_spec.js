import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoReadinessOrbitRow from 'ee/ai/settings/readiness/components/duo_readiness_orbit_row.vue';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import orbitLastIndexedQuery from 'ee/ai/settings/readiness/graphql/queries/orbit_last_indexed.query.graphql';
import orbitGroupLastIndexedQuery from 'ee/ai/settings/readiness/graphql/queries/orbit_group_last_indexed.query.graphql';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('DuoReadinessOrbitRow', () => {
  let wrapper;
  let mutationHandler;
  let lastIndexedHandler;
  let groupLastIndexedHandler;

  const defaultOrbit = {
    enabled: false,
    canEnable: false,
    canStartTrial: false,
    rootGroupPath: 'gitlab-org',
    graphPath: '/-/dashboard/orbit',
    settingsPath: '/gitlab-org/-/settings/orbit',
  };

  const lastIndexedResponse = (lastCompletedAt) => ({
    data: {
      project: {
        __typename: 'Project',
        id: 'gid://gitlab/Project/1',
        orbit: {
          __typename: 'OrbitNamespace',
          indexing: { __typename: 'OrbitIndexing', lastCompletedAt },
        },
      },
    },
  });

  const groupLastIndexedResponse = (lastCompletedAt) => ({
    data: {
      group: {
        __typename: 'Group',
        id: 'gid://gitlab/Group/2',
        orbit: {
          __typename: 'OrbitNamespace',
          indexing: { __typename: 'OrbitIndexing', lastCompletedAt },
        },
      },
    },
  });

  const successResponse = {
    data: {
      orbitUpdate: {
        group: {
          id: 'gid://gitlab/Group/1',
          name: 'gitlab-org',
          fullPath: 'gitlab-org',
          orbit: { enabled: true, __typename: 'OrbitNamespace' },
          __typename: 'Group',
        },
        errors: [],
        __typename: 'OrbitUpdatePayload',
      },
    },
  };

  const createComponent = ({
    orbit = {},
    props = {},
    handler = jest.fn().mockResolvedValue(successResponse),
  } = {}) => {
    mutationHandler = handler;
    wrapper = mountExtended(DuoReadinessOrbitRow, {
      apolloProvider: createMockApollo([
        [orbitUpdateMutation, mutationHandler],
        [orbitLastIndexedQuery, lastIndexedHandler],
        [orbitGroupLastIndexedQuery, groupLastIndexedHandler],
      ]),
      propsData: {
        orbit: { ...defaultOrbit, ...orbit },
        fullPath: 'gitlab-org/gitlab',
        ...props,
      },
    });
  };

  const findRow = () => wrapper.findComponent(DuoReadinessRow);
  const findBetaBadge = () => wrapper.findByTestId('orbit-beta-badge');
  const findEnableButton = () => wrapper.findComponentByTestId('orbit-enable-button');
  const findStartTrialButton = () => wrapper.findByTestId('orbit-start-trial-button');
  const findQueryGraphButton = () => wrapper.findByTestId('orbit-query-graph-button');
  const findLockIcon = () => wrapper.findComponent(CascadingLockIcon);

  beforeEach(() => {
    lastIndexedHandler = jest.fn().mockResolvedValue(lastIndexedResponse(null));
    groupLastIndexedHandler = jest.fn().mockResolvedValue(groupLastIndexedResponse(null));
  });

  describe('when Orbit is not enabled', () => {
    it('renders a neutral to-do row that names who can turn it on', () => {
      createComponent();

      expect(findRow().props('title')).toBe('GitLab Orbit');
      expect(findRow().props('status')).toBe('todo');
      expect(findRow().props('description')).toBe(
        'A knowledge graph that helps agents reason across your whole project. Only a Group Owner can turn it on.',
      );
    });

    it('does not read the indexing state', () => {
      createComponent();

      expect(lastIndexedHandler).not.toHaveBeenCalled();
    });

    describe('when the user cannot enable it', () => {
      it('offers no control', () => {
        createComponent();

        expect(findEnableButton().exists()).toBe(false);
        expect(findQueryGraphButton().exists()).toBe(false);
      });
    });

    describe('when the user can enable it', () => {
      it('offers Enable', () => {
        createComponent({ orbit: { canEnable: true } });

        expect(findEnableButton().text()).toBe('Enable');
        expect(findRow().props('description')).toBe(
          'A knowledge graph that helps agents reason across your whole project.',
        );
      });
    });

    describe('when the user can start a trial', () => {
      beforeEach(() => {
        createComponent({ orbit: { canStartTrial: true } });
      });

      it('links to the group Orbit settings page', () => {
        expect(findStartTrialButton().text()).toBe('Start trial');
        expect(findStartTrialButton().attributes('href')).toBe('/gitlab-org/-/settings/orbit');
      });

      it('offers no Enable button', () => {
        expect(findEnableButton().exists()).toBe(false);
      });
    });
  });

  describe('enabling', () => {
    it('calls the mutation for the root group and flips the row to done', async () => {
      createComponent({ orbit: { canEnable: true } });

      findEnableButton().trigger('click');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: { groupPath: 'gitlab-org', enabled: true },
      });
      expect(findRow().props('status')).toBe('done');
      expect(findQueryGraphButton().exists()).toBe(true);
      expect(lastIndexedHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab' });
    });

    it('keeps the row as to-do and alerts when the mutation returns errors', async () => {
      createComponent({
        orbit: { canEnable: true },
        handler: jest.fn().mockResolvedValue({
          data: {
            orbitUpdate: { group: null, errors: ['not allowed'], __typename: 'OrbitUpdatePayload' },
          },
        }),
      });

      findEnableButton().trigger('click');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Something went wrong while turning on GitLab Orbit.',
        }),
      );
      expect(findRow().props('status')).toBe('todo');
    });
  });

  describe('when Orbit is enabled', () => {
    it('reads the indexing state of the project and shows freshness', async () => {
      lastIndexedHandler.mockResolvedValue(lastIndexedResponse('2020-07-05T10:00:00Z'));
      createComponent({ orbit: { enabled: true } });
      await waitForPromises();

      expect(lastIndexedHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab' });
      expect(findRow().props('description')).toMatch(
        /^Indexed .+\. Agents get repo-wide context\.$/,
      );
      expect(findQueryGraphButton().attributes('href')).toBe('/-/dashboard/orbit');
    });

    it('shows a generic description before the first indexing run completes', async () => {
      createComponent({ orbit: { enabled: true } });
      await waitForPromises();

      expect(findRow().props('description')).toBe('Agents get repo-wide context.');
    });

    describe('when the status read fails', () => {
      it('falls back to a generic description and reports the error', async () => {
        lastIndexedHandler.mockRejectedValue(new Error('unavailable'));
        createComponent({ orbit: { enabled: true } });
        await waitForPromises();

        expect(findRow().props('description')).toBe('Agents get repo-wide context.');
        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      });

      it('does not report an Orbit error to Sentry', async () => {
        lastIndexedHandler.mockResolvedValue({ errors: [{ message: 'Orbit request failed' }] });
        createComponent({ orbit: { enabled: true } });
        await waitForPromises();

        expect(findRow().props('description')).toBe('Agents get repo-wide context.');
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });
  });

  describe('on a group', () => {
    const definition = 'A knowledge graph that helps agents reason across whole projects.';

    const createGroupComponent = (orbit = {}) =>
      createComponent({ orbit, props: { group: true, fullPath: 'gitlab-org/subgroup' } });

    it('renders a Beta badge and the definition as a to-do', () => {
      createGroupComponent({ canEnable: true });

      expect(findBetaBadge().text()).toBe('Beta');
      expect(findRow().props('status')).toBe('todo');
      expect(findRow().props('description')).toBe(definition);
    });

    it('names who can turn it on, with no control, on a top-level group the viewer cannot change', () => {
      createGroupComponent();

      expect(findRow().props('description')).toBe(
        `${definition} Only a Group Owner can turn it on.`,
      );
      expect(findEnableButton().exists()).toBe(false);
      expect(findStartTrialButton().exists()).toBe(false);
      expect(findLockIcon().exists()).toBe(false);
    });

    it('does not read the indexing state while Orbit is off', () => {
      createGroupComponent();

      expect(groupLastIndexedHandler).not.toHaveBeenCalled();
      expect(lastIndexedHandler).not.toHaveBeenCalled();
    });

    it('offers Enable on a top-level group that can turn it on', () => {
      createGroupComponent({ canEnable: true });

      expect(findEnableButton().text()).toBe('Enable');
      expect(findEnableButton().props('disabled')).toBe(false);
      expect(findLockIcon().exists()).toBe(false);
      expect(findStartTrialButton().exists()).toBe(false);
    });

    it('offers Start trial on a top-level group that can start one', () => {
      createGroupComponent({ canEnable: true, canStartTrial: true });

      expect(findStartTrialButton().attributes('href')).toBe('/gitlab-org/-/settings/orbit');
      expect(findEnableButton().exists()).toBe(false);
    });

    it('turns Orbit on for the top-level group and reads the group indexing state', async () => {
      createGroupComponent({ canEnable: true });

      findEnableButton().trigger('click');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: { groupPath: 'gitlab-org', enabled: true },
      });
      expect(findRow().props('status')).toBe('done');
      expect(findQueryGraphButton().exists()).toBe(true);
      expect(groupLastIndexedHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/subgroup' });
      expect(lastIndexedHandler).not.toHaveBeenCalled();
    });

    describe('on a subgroup', () => {
      const cascadingSettings = {
        lockedByAncestor: true,
        lockedByApplicationSetting: false,
        ancestorNamespace: { fullName: 'GitLab.org', path: '/groups/gitlab-org/-/edit' },
      };

      it('locks Enable to the top-level group', () => {
        createGroupComponent({ cascadingSettings });

        expect(findEnableButton().props('disabled')).toBe(true);
        expect(findLockIcon().props()).toMatchObject({
          isLockedByGroupAncestor: true,
          isLockedByApplicationSettings: false,
          ancestorNamespace: cascadingSettings.ancestorNamespace,
        });
      });

      it('keeps Query graph once the top-level group turned Orbit on', () => {
        createGroupComponent({ cascadingSettings, enabled: true });

        expect(findQueryGraphButton().exists()).toBe(true);
        expect(findEnableButton().exists()).toBe(false);
        expect(findLockIcon().exists()).toBe(true);
      });
    });

    describe('when Orbit is enabled', () => {
      it('reads the group indexing state and adds freshness to the definition', async () => {
        groupLastIndexedHandler.mockResolvedValue(groupLastIndexedResponse('2020-07-05T10:00:00Z'));
        createGroupComponent({ enabled: true });
        await waitForPromises();

        expect(groupLastIndexedHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/subgroup' });
        expect(findRow().props('status')).toBe('done');
        expect(findRow().props('description')).toMatch(
          /^A knowledge graph that helps agents reason across whole projects\. Indexed .+\.$/,
        );
      });

      it('keeps the definition only when the status read fails', async () => {
        groupLastIndexedHandler.mockRejectedValue(new Error('unavailable'));
        createGroupComponent({ enabled: true });
        await waitForPromises();

        expect(findRow().props('description')).toBe(definition);
        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
      });
    });
  });
});
