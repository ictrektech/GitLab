import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlDisclosureDropdown, GlIcon, GlAvatarsInline, GlSprintf } from '@gitlab/ui';
import { createMockSubscription as createMockApolloSubscription } from 'mock-apollo-client';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import Api from 'ee/api';
import { createAlert } from '~/alert';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useLocalStorageSpy } from 'helpers/local_storage_helper';
import { AVAILABILITY_STATUS } from '~/set_status_modal/constants';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import LocalStorageSync from '~/vue_shared/components/local_storage_sync.vue';
import ReviewerAvatarLink from '~/sidebar/components/reviewers/reviewer_avatar_link.vue';
import SuggestedReviewers from 'ee/merge_requests/components/reviewers/suggested_reviewers.vue';
import suggestedReviewersQuery from 'ee/merge_requests/queries/suggested_reviewer.query.graphql';
import aiSuggestedReviewersSubscription from 'ee/merge_requests/queries/ai_suggested_reviewers.subscription.graphql';
import setReviewersMutation from '~/merge_requests/components/reviewers/queries/set_reviewers.mutation.graphql';

jest.mock('ee/api');
jest.mock('~/alert');

Vue.use(VueApollo);

const STORAGE_KEY = 'suggested_reviewers_collapsed';

const rule = (id, name, { type = 'REGULAR', section = null, patterns = null } = {}) => ({
  id: `gid://gitlab/ApprovalRule/${id}`,
  name,
  type,
  section,
  patterns,
});

const suggestion = (
  id,
  username,
  { approvalRule = null, reason = 'Owns the changed files.', availability = null } = {},
) => ({
  __typename: 'AiSuggestedReviewer',
  id: `gid://gitlab/MergeRequests::AiSuggestedReviewer/${id}`,
  user: {
    __typename: 'UserCore',
    id: `gid://gitlab/User/${id}`,
    username,
    name: username,
    avatarUrl: '/avatar.png',
    webUrl: `/${username}`,
    webPath: `/${username}`,
    status: availability ? { __typename: 'UserStatus', availability } : null,
  },
  approvalRule: approvalRule && { __typename: 'ApprovalRule', ...approvalRule },
  reason,
  createdAt: '2026-09-20T10:00:00Z',
});

const workflow = (
  id,
  { definition = 'recommend_reviewers/v1', statusGroup = 'COMPLETED' } = {},
) => ({
  __typename: 'DuoWorkflow',
  id: `gid://gitlab/Ai::DuoWorkflows::Workflow/${id}`,
  workflowDefinition: definition,
  statusGroup,
});

const OLD_MR_CREATED_AT = '2020-01-01T00:00:00Z';

const mockData = (nodes, { workflows = [workflow(1)], createdAt = OLD_MR_CREATED_AT } = {}) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/1',
      mergeRequest: {
        __typename: 'MergeRequest',
        id: 'gid://gitlab/MergeRequest/1',
        createdAt,
        duoWorkflows: workflows && {
          __typename: 'DuoWorkflowConnection',
          nodes: workflows,
        },
        aiSuggestedReviewers: {
          __typename: 'AiSuggestedReviewerConnection',
          nodes,
        },
      },
    },
  },
});

describe('Suggested reviewers component', () => {
  useLocalStorageSpy();

  let wrapper;
  let queryHandler;
  let mutationHandler;
  let mockedSubscription;

  const findRows = () => wrapper.findAllByTestId('reviewer');
  const findAddButtons = () => wrapper.findAllComponentsByTestId('add-reviewer');
  const findToggle = () => wrapper.findByTestId('suggested-reviewers-toggle');
  const findRowsContainer = () => wrapper.findByTestId('suggested-reviewers-rows');
  const findChipStack = () => wrapper.findComponent(GlAvatarsInline);
  const findLocalStorageSync = () => wrapper.findComponent(LocalStorageSync);
  const findReasonIcon = () =>
    wrapper
      .findAllComponents(GlIcon)
      .wrappers.find((icon) => icon.classes('suggested-reviewer-reason-icon'));
  const findFirstAvatarLink = () => wrapper.findComponent(ReviewerAvatarLink);
  const usernamesInRows = () =>
    findRows().wrappers.map((row) => row.findComponent(ReviewerAvatarLink).props('user').username);

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findDropdownToggle = () => wrapper.findComponentByTestId('actions-toggle');
  const retry = () => findDropdown().props('items')[0].action();

  const findFetchPrompt = () => wrapper.findByTestId('fetch-recommendations-prompt');
  const findFetchButton = () => wrapper.findComponentByTestId('fetch-recommendations');

  const emitSubscriptionUpdate = (nodes) => {
    mockedSubscription.next({
      data: {
        mergeRequestAiSuggestedReviewersUpdated: {
          __typename: 'MergeRequest',
          id: 'gid://gitlab/MergeRequest/1',
          aiSuggestedReviewers: {
            __typename: 'AiSuggestedReviewerConnection',
            nodes,
          },
        },
      },
    });
    return waitForPromises();
  };

  const createComponent = (
    nodes,
    canUpdate = true,
    { queryResponses = [mockData(nodes)] } = {},
  ) => {
    Api.triggerDuoFlow.mockResolvedValue({});

    queryHandler = jest.fn();
    queryResponses.forEach((response) => queryHandler.mockResolvedValueOnce(response));
    queryHandler.mockResolvedValue(queryResponses.at(-1));

    mutationHandler = jest.fn().mockResolvedValue({
      data: {
        mergeRequestSetReviewers: { __typename: 'MergeRequestSetReviewersPayload', errors: [] },
      },
    });

    mockedSubscription = createMockApolloSubscription();

    const apolloProvider = createMockApollo([
      [suggestedReviewersQuery, queryHandler],
      [setReviewersMutation, mutationHandler],
    ]);

    apolloProvider.defaultClient.setRequestHandler(
      aiSuggestedReviewersSubscription,
      () => mockedSubscription,
    );

    wrapper = shallowMountExtended(SuggestedReviewers, {
      apolloProvider,
      provide: { projectPath: 'group/project', issuableId: '1', issuableIid: '1' },
      propsData: {
        canUpdate,
      },
      stubs: {
        GlSprintf,
        GlDisclosureDropdown: stubComponent(GlDisclosureDropdown, {
          template: '<div><slot name="toggle"></slot></div>',
        }),
        // Render the popover's title + default slot so assertions work.
        GlPopover: {
          props: ['title'],
          template:
            '<div><span data-testid="patterns-popover-title">{{ title }}</span><slot></slot></div>',
        },
        // Render the scoped avatar slot so each chip is a ReviewerAvatarLink.
        GlAvatarsInline: {
          props: ['avatars', 'maxVisible', 'avatarSize', 'badgeSrOnlyText'],
          template:
            '<div><template v-for="avatar in avatars.slice(0, maxVisible)"><slot name="avatar" :avatar="avatar" /></template></div>',
        },
      },
    });

    return waitForPromises();
  };

  it('renders nothing when there are no suggestions', async () => {
    await createComponent([]);

    expect(wrapper.text()).toBe('');
    expect(findToggle().exists()).toBe(false);
  });

  it('renders one row per reviewer without grouping by approval rule', async () => {
    await createComponent([
      suggestion(1, 'alice', { approvalRule: rule(1, 'Backend') }),
      suggestion(2, 'bob'),
      suggestion(3, 'carol', { approvalRule: rule(1, 'Backend') }),
    ]);

    expect(findRows()).toHaveLength(3);
    expect(usernamesInRows()).toEqual(['alice', 'bob', 'carol']);
  });

  describe('role line', () => {
    it('renders the rule section name on the reviewer row', async () => {
      await createComponent([
        suggestion(1, 'alice', { approvalRule: rule(1, 'Any', { type: 'ANY_APPROVER' }) }),
      ]);

      expect(wrapper.findByTestId('reviewer-role').text()).toBe('Any eligible user');
    });

    it('does not render a role line when the reviewer has no approval rule', async () => {
      await createComponent([suggestion(1, 'alice')]);

      expect(wrapper.findByTestId('reviewer-role').exists()).toBe(false);
      expect(wrapper.findByTestId('rule-patterns').exists()).toBe(false);
    });
  });

  describe('recommendation reason', () => {
    it('shows the status-active icon and passes the reason to the avatar link for the user popover', async () => {
      await createComponent([suggestion(1, 'alice', { reason: 'Owns the changed files.' })]);

      expect(findReasonIcon().exists()).toBe(true);
      expect(findFirstAvatarLink().attributes('data-recommendation-reason')).toBe(
        'Owns the changed files.',
      );
    });

    it('does not render the icon or pass a reason when there is no reason', async () => {
      await createComponent([suggestion(1, 'alice', { reason: '' })]);

      expect(findReasonIcon()).toBeUndefined();
      expect(findFirstAvatarLink().attributes('data-recommendation-reason')).toBeUndefined();
    });

    it('uses the status-active icon in info variant when the reviewer is available', async () => {
      await createComponent([
        suggestion(1, 'alice', { availability: AVAILABILITY_STATUS.NOT_SET }),
      ]);

      expect(findReasonIcon().props('name')).toBe('status-active');
      expect(findReasonIcon().props('variant')).toBe('info');
    });

    it('uses the status-waiting icon in subtle variant when the reviewer is busy', async () => {
      await createComponent([suggestion(1, 'alice', { availability: AVAILABILITY_STATUS.BUSY })]);

      expect(findReasonIcon().props('name')).toBe('status-waiting');
      expect(findReasonIcon().props('variant')).toBe('subtle');
    });

    it('shows when the recommendation was made below the header', async () => {
      await createComponent([suggestion(1, 'alice'), suggestion(2, 'bob')]);

      expect(wrapper.findByTestId('recommendation-created-at').text()).toContain('Generated');
      expect(wrapper.findComponent(TimeAgoTooltip).props('time')).toBe('2026-09-20T10:00:00Z');
    });
  });

  describe('matching files', () => {
    const findPatternsTrigger = () => wrapper.findByTestId('rule-patterns');
    const patternsIn = () => wrapper.findAllByTestId('matching-file').wrappers.map((w) => w.text());
    const findPopoverTitle = () => wrapper.findByTestId('patterns-popover-title');

    it('renders the section name as an interactive trigger with the patterns in a popover', async () => {
      await createComponent([
        suggestion(1, 'alice', {
          approvalRule: rule(1, 'Codeowners rule', {
            section: 'Backend',
            patterns: ['*.rb', '*.rake'],
          }),
        }),
      ]);

      expect(findPatternsTrigger().text()).toBe('Backend');
      // Visible label stays first so it remains the accessible name (WCAG 2.5.3).
      expect(findPatternsTrigger().attributes('aria-label')).toBe(
        'Backend, matching files: *.rb, *.rake',
      );
      expect(findPopoverTitle().text()).toBe('Matching files');
      expect(patternsIn()).toEqual(['*.rb', '*.rake']);
    });

    it('renders the rule name as plain text with no popover for the default codeowners section', async () => {
      await createComponent([
        suggestion(1, 'alice', {
          approvalRule: rule(1, 'Code owners rule', { section: 'codeowners', patterns: ['*.rb'] }),
        }),
      ]);

      expect(wrapper.findByTestId('reviewer-role').text()).toBe('Code owners rule');
      expect(findPatternsTrigger().exists()).toBe(false);
      expect(patternsIn()).toEqual([]);
    });
  });

  describe('adding a reviewer', () => {
    it('adds the suggested reviewer without replacing the existing ones', async () => {
      await createComponent([suggestion(1, 'alice'), suggestion(2, 'bob')]);

      findAddButtons().at(0).vm.$emit('click');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        reviewerUsernames: ['alice'],
        projectPath: 'group/project',
        iid: '1',
        operationMode: 'APPEND',
      });
    });

    it('hides add buttons if the user does not have permission', async () => {
      await createComponent([suggestion(1, 'alice')], false);

      expect(findAddButtons()).toHaveLength(0);
    });

    it('renders nothing once the last reviewer has been added and the list is empty', async () => {
      await createComponent([suggestion(1, 'alice')]);

      mockedSubscription.next({
        data: {
          mergeRequestAiSuggestedReviewersUpdated: {
            __typename: 'MergeRequest',
            id: 'gid://gitlab/MergeRequest/1',
            aiSuggestedReviewers: {
              __typename: 'AiSuggestedReviewerConnection',
              nodes: [],
            },
          },
        },
      });
      await waitForPromises();

      expect(wrapper.text()).toBe('');
    });

    it('replaces the rendered suggestions when the subscription updates', async () => {
      await createComponent([suggestion(1, 'alice')]);

      mockedSubscription.next({
        data: {
          mergeRequestAiSuggestedReviewersUpdated: {
            __typename: 'MergeRequest',
            id: 'gid://gitlab/MergeRequest/1',
            aiSuggestedReviewers: {
              __typename: 'AiSuggestedReviewerConnection',
              nodes: [suggestion(2, 'bob')],
            },
          },
        },
      });
      await waitForPromises();

      expect(usernamesInRows()).toEqual(['bob']);
    });
  });

  describe('retry action', () => {
    it('is hidden if the user does not have permission', async () => {
      await createComponent([suggestion(1, 'alice')], false);

      expect(findDropdown().exists()).toBe(false);
    });

    it('triggers the recommend reviewers flow', async () => {
      await createComponent([suggestion(1, 'alice')]);

      retry();
      await waitForPromises();

      expect(Api.triggerDuoFlow).toHaveBeenCalledWith('recommend_reviewers/v1', {
        project_id: 'group/project',
        merge_request_id: '1',
        goal: '1',
      });
    });

    it('alerts when the flow fails to start', async () => {
      await createComponent([suggestion(1, 'alice')]);
      Api.triggerDuoFlow.mockRejectedValue(new Error('nope'));

      retry();
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Could not generate new reviewer recommendations. Try again later.',
        }),
      );
      expect(findDropdownToggle().props('loading')).toBe(false);
    });
  });

  describe('fetch prompt', () => {
    const neverRun = (options = {}) => ({
      queryResponses: [mockData([], { workflows: [], ...options })],
    });

    describe('when the flow has never run on the merge request', () => {
      beforeEach(() => createComponent([], true, neverRun()));

      it('renders the prompt with an enabled generate button', () => {
        expect(findFetchPrompt().text()).toContain('Recommended');
        expect(findFetchButton().text()).toBe('Generate');
        expect(findFetchButton().attributes('aria-label')).toBe('Generate recommended reviewers');
        expect(findFetchButton().props('loading')).toBe(false);
      });

      it('does not render the suggestions list', () => {
        expect(findToggle().exists()).toBe(false);
      });

      describe('when generate is selected', () => {
        beforeEach(async () => {
          findFetchButton().vm.$emit('click');
          await waitForPromises();
        });

        it('triggers the recommend reviewers flow', () => {
          expect(Api.triggerDuoFlow).toHaveBeenCalledWith('recommend_reviewers/v1', {
            project_id: 'group/project',
            merge_request_id: '1',
            goal: '1',
          });
        });

        it('keeps the generate button disabled while the flow runs', () => {
          expect(findFetchButton().props('loading')).toBe(true);
        });

        it('replaces the prompt with the list when suggestions arrive', async () => {
          await emitSubscriptionUpdate([suggestion(1, 'alice')]);

          expect(findFetchPrompt().exists()).toBe(false);
          expect(usernamesInRows()).toEqual(['alice']);
        });

        describe('when an update without suggestions arrives', () => {
          it('refetches and hides the prompt once the run has completed', async () => {
            queryHandler.mockResolvedValue(mockData([], { workflows: [workflow(1)] }));

            await emitSubscriptionUpdate([]);

            expect(queryHandler).toHaveBeenCalledTimes(2);
            expect(wrapper.text()).toBe('');
          });

          it('refetches and keeps the generate button disabled while the run is active', async () => {
            queryHandler.mockResolvedValue(
              mockData([], { workflows: [workflow(1, { statusGroup: 'ACTIVE' })] }),
            );

            await emitSubscriptionUpdate([]);

            expect(queryHandler).toHaveBeenCalledTimes(2);
            expect(findFetchButton().props('loading')).toBe(true);
          });
        });
      });

      describe('when the flow fails to start', () => {
        beforeEach(async () => {
          Api.triggerDuoFlow.mockRejectedValue(new Error('nope'));

          findFetchButton().vm.$emit('click');
          await waitForPromises();
        });

        it('alerts and re-enables the generate button', () => {
          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message: 'Could not generate new reviewer recommendations. Try again later.',
            }),
          );
          expect(findFetchButton().props('loading')).toBe(false);
        });
      });
    });

    describe('when only another flow has run on the merge request', () => {
      beforeEach(() =>
        createComponent(
          [],
          true,
          neverRun({
            workflows: [workflow(2, { definition: 'code_review/v1', statusGroup: 'ACTIVE' })],
          }),
        ),
      );

      it('renders an enabled generate button', () => {
        expect(findFetchButton().props('loading')).toBe(false);
      });
    });

    describe('when the flow is running', () => {
      beforeEach(() =>
        createComponent(
          [],
          true,
          neverRun({ workflows: [workflow(1, { statusGroup: 'ACTIVE' })] }),
        ),
      );

      it('renders a disabled generate button', () => {
        expect(findFetchButton().props('loading')).toBe(true);
      });

      describe('when a reviewer change sends an update without suggestions', () => {
        beforeEach(() => emitSubscriptionUpdate([]));

        it('keeps the prompt with a disabled generate button', () => {
          expect(queryHandler).toHaveBeenCalledTimes(2);
          expect(findFetchButton().props('loading')).toBe(true);
        });
      });
    });

    describe.each(['COMPLETED', 'FAILED'])('when the flow has a %s run', (statusGroup) => {
      beforeEach(() =>
        createComponent([], true, neverRun({ workflows: [workflow(1, { statusGroup })] })),
      );

      it('renders nothing', () => {
        expect(wrapper.text()).toBe('');
      });
    });

    describe('when the user cannot update the merge request', () => {
      beforeEach(() => createComponent([], false, neverRun()));

      it('renders nothing', () => {
        expect(wrapper.text()).toBe('');
      });
    });

    describe('when workflows are unavailable', () => {
      beforeEach(() => createComponent([], true, neverRun({ workflows: null })));

      it('renders nothing', () => {
        expect(wrapper.text()).toBe('');
      });
    });

    describe('when the merge request was just created', () => {
      const justCreated = () => new Date(Date.now() - 30 * 1000).toISOString();

      describe('and the automatic run has not started after the grace period', () => {
        beforeEach(() =>
          createComponent([], true, {
            queryResponses: [
              mockData([], { workflows: [], createdAt: justCreated() }),
              mockData([], { workflows: [] }),
            ],
          }),
        );

        it('disables the generate button while waiting for the automatic run', () => {
          expect(findFetchButton().props('loading')).toBe(true);
        });

        it('refetches and enables the generate button once the grace period ends', async () => {
          jest.advanceTimersByTime(90 * 1000);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(2);
          expect(findFetchButton().props('loading')).toBe(false);
        });

        describe('when a reviewer change sends an update without suggestions', () => {
          beforeEach(() => emitSubscriptionUpdate([]));

          it('keeps the generate button disabled until the grace period ends', () => {
            expect(findFetchPrompt().exists()).toBe(true);
            expect(findFetchButton().props('loading')).toBe(true);
          });
        });

        it('does not refetch after the component is destroyed', async () => {
          wrapper.destroy();
          jest.runOnlyPendingTimers();
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('and the automatic run is in progress after the grace period', () => {
        beforeEach(() =>
          createComponent([], true, {
            queryResponses: [
              mockData([], { workflows: [], createdAt: justCreated() }),
              mockData([], { workflows: [workflow(1, { statusGroup: 'ACTIVE' })] }),
            ],
          }),
        );

        it('keeps the generate button disabled', async () => {
          jest.advanceTimersByTime(90 * 1000);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(2);
          expect(findFetchButton().props('loading')).toBe(true);
        });
      });

      describe('and the automatic run completes without suggestions before the grace period ends', () => {
        beforeEach(async () => {
          await createComponent([], true, {
            queryResponses: [
              mockData([], { workflows: [], createdAt: justCreated() }),
              mockData([], { workflows: [workflow(1)] }),
            ],
          });
          await emitSubscriptionUpdate([]);
        });

        it('hides the prompt without waiting for the grace period', () => {
          expect(queryHandler).toHaveBeenCalledTimes(2);
          expect(findFetchPrompt().exists()).toBe(false);
        });

        it('does not refetch when the grace period would have ended', async () => {
          jest.runOnlyPendingTimers();
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(2);
        });
      });

      describe('and the client clock is behind the server', () => {
        beforeEach(() =>
          createComponent([], true, {
            queryResponses: [
              mockData([], {
                workflows: [],
                createdAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
              }),
              mockData([], { workflows: [] }),
            ],
          }),
        );

        it('waits no longer than the grace period', async () => {
          jest.advanceTimersByTime(2 * 60 * 1000);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(2);
          expect(findFetchButton().props('loading')).toBe(false);
        });
      });
    });
  });

  describe('collapse toggle', () => {
    it('is expanded by default and shows the rows', async () => {
      await createComponent([suggestion(1, 'alice')]);

      expect(findToggle().attributes('aria-expanded')).toBe('true');
      expect(findRowsContainer().isVisible()).toBe(true);
      expect(findChipStack().exists()).toBe(false);
    });

    it('collapses when the header is clicked, hiding the rows and showing the chips', async () => {
      await createComponent([suggestion(1, 'alice')]);

      await findToggle().trigger('click');

      expect(findToggle().attributes('aria-expanded')).toBe('false');
      expect(findRowsContainer().isVisible()).toBe(false);
      expect(findChipStack().exists()).toBe(true);
    });

    it('links the toggle to the rows via aria-controls', async () => {
      await createComponent([suggestion(1, 'alice')]);

      expect(findToggle().attributes('aria-controls')).toBe('suggested-reviewers-rows');
      expect(findRowsContainer().attributes('id')).toBe('suggested-reviewers-rows');
    });

    it('sets an accessible label describing the collapse action', async () => {
      await createComponent([suggestion(1, 'alice')]);

      expect(findToggle().attributes('aria-label')).toBe('Collapse recommended reviewers');

      await findToggle().trigger('click');

      expect(findToggle().attributes('aria-label')).toBe('Expand recommended reviewers');
    });
  });

  describe('collapsed chips', () => {
    beforeEach(async () => {
      await createComponent([
        suggestion(1, 'alice'),
        suggestion(2, 'bob'),
        suggestion(3, 'carol'),
        suggestion(4, 'dave'),
      ]);
      await findToggle().trigger('click');
    });

    it('shows a stacked avatar group of at most three chips with an overflow badge', () => {
      expect(findChipStack().props('avatars')).toHaveLength(4);
      expect(findChipStack().props('maxVisible')).toBe(3);
      expect(findChipStack().props('avatarSize')).toBe(24);
      expect(findChipStack().props('badgeSrOnlyText')).toBe('1 more recommended reviewer');
    });

    it('gives the chip stack a single accessible label for the whole group', () => {
      expect(findChipStack().attributes('aria-label')).toBe('4 recommended reviewers');
      expect(findChipStack().attributes('role')).toBe('group');
    });

    it('renders the chip stack outside the toggle button so chip links do not toggle collapse', () => {
      expect(findToggle().find('[data-testid="collapsed-chips"]').exists()).toBe(false);
    });

    it('hides when the recommendation was made', () => {
      expect(wrapper.findByTestId('recommendation-created-at').exists()).toBe(false);
    });

    it('renders each chip as an avatar link that keeps the user popover data', () => {
      const chips = wrapper.findAllComponentsByTestId('collapsed-chip');

      expect(chips).toHaveLength(3);
      expect(chips.at(0).props('user').username).toBe('alice');
      expect(chips.at(0).attributes('data-recommendation-reason')).toBe('Owns the changed files.');
    });
  });

  describe('persistence', () => {
    it('syncs the collapsed state to localStorage under a shared key', async () => {
      await createComponent([suggestion(1, 'alice')]);

      expect(findLocalStorageSync().props('storageKey')).toBe(STORAGE_KEY);
      expect(findLocalStorageSync().props('value')).toBe(false);

      await findToggle().trigger('click');

      expect(findLocalStorageSync().props('value')).toBe(true);
    });

    it('restores the collapsed state emitted by localStorage', async () => {
      await createComponent([suggestion(1, 'alice')]);

      findLocalStorageSync().vm.$emit('input', true);
      await waitForPromises();

      expect(findToggle().attributes('aria-expanded')).toBe('false');
      expect(findChipStack().exists()).toBe(true);
    });
  });
});
