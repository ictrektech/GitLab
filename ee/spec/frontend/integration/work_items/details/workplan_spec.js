import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { within } from '@testing-library/vue';
import { http, HttpResponse } from 'msw';
import workItemDecisionsFixture from 'test_fixtures/graphql/work_items/integration/work_item_decisions.query.graphql.json';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import * as urlUtility from '~/lib/utils/url_utility';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  findIssueToEdit,
  findWorkItemDetail,
  selectIssue,
  createPortalElement,
} from 'ee_jest/integration/work_items/test_helpers';
import { setFeatureFlags, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  snapshotRequests,
  expectGraphQLCalls,
  lastRequestVariables,
  captureRequest,
} from 'ee_jest/integration/core/operation_helpers';
import { server } from 'ee_jest/integration/server';
import {
  namespaceWorkItem,
  workItemAgentPlan,
  workItemNotesByIid,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  assignRouter,
  fullMount,
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { FORBIDDEN_LIST_REFETCHES } from '../drawer_shared_test_helpers';

Vue.use(VueApollo);

describe('Work item workplan integration test', () => {
  const { bindInternalEventDocument } = useMockInternalEventsTracking();
  let trackEventSpy;
  const viewEvents = () =>
    trackEventSpy.mock.calls.filter(([event]) => event === 'view_work_item_workplan');
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  const withinDrawer = () => within(document.getElementById('contextual-panel-portal'));
  const findInlineRow = () => withinDrawer().queryByTestId('workplan-inline-row');
  const findOpenButton = () => withinDrawer().queryByTestId('open-workplan-button');
  const findRenderedPlan = () => withinDrawer().queryByTestId('workplan-rendered');
  const findEmptyState = () => withinDrawer().queryByTestId('workplan-empty-state');
  const findWorkplanEditor = () => withinDrawer().queryByTestId('workplan-editor');
  const findCreateWorkplanDropdown = () => withinDrawer().queryByTestId('create-workplan-dropdown');
  const findPlanCta = () => withinDrawer().queryByTestId('work-item-plan-cta');
  const findPanelEditButton = () => withinDrawer().queryByTestId('panel-edit-button');
  const findSaveButton = () => withinDrawer().queryByTestId('save-workplan-button');
  const findEditorTextarea = () => findWorkplanEditor()?.querySelector('textarea');
  const findDuoQuestionOption = () =>
    withinDrawer().queryAllByTestId('duo-question-option')[0] ?? null;
  const findMediumReadiness = () => withinDrawer().queryByLabelText('Readiness: Medium');
  const mountAndOpenWorkItem = async ({ glFeatures = {} } = {}) => {
    setFeatureFlags(glFeatures);

    fullMount(WorkItemsRoot, {
      router,
      propsData: {
        rootPageFullPath: 'gitlab-org/gitlab',
      },
      apolloProvider,
      provide: {
        isGroup: false,
        fullPath: 'gitlab-org/gitlab',
        groupPath: 'gitlab-org',
        workItemType: 'Issue',
        isSignedIn: true,
        initialSort: 'created_desc',
        isServiceDeskSupported: false,
      },
    });

    await waitForElement(findIssueToEdit);
    await selectIssue();
  };

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    ({ trackEventSpy } = bindInternalEventDocument());
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when the work item has no agent plan widget', () => {
    beforeEach(async () => {
      await mountAndOpenWorkItem();
    });

    it('does not render the workplan', async () => {
      await waitForElement(findWorkItemDetail);

      expect(findInlineRow()).toBe(null);
    });
  });

  describe('when the work item has an agent plan widget with AI disabled', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItem).withAgentPlanAiDisabled();
      await mountAndOpenWorkItem();
    });

    it('does not render the workplan but shows the Plan CTA', async () => {
      await waitForElement(findWorkItemDetail);
      await waitForElement(findPlanCta);

      expect(findInlineRow()).toBe(null);
    });

    describe('when the user clicks the Plan CTA', () => {
      beforeEach(async () => {
        await waitForElement(findWorkItemDetail);
        await waitAndClick(findPlanCta);
      });

      it('reveals the workplan and hides the CTA', async () => {
        await waitForElement(findInlineRow);

        expect(findPlanCta()).toBe(null);
      });
    });

    describe('when the user selects Create manually from the Plan CTA', () => {
      let visitUrlSpy;

      beforeEach(async () => {
        visitUrlSpy = jest.spyOn(urlUtility, 'visitUrl').mockImplementation(() => {});
        await waitForElement(findPlanCta);
        const dropdownToggle = await waitForElement(() =>
          within(withinDrawer().queryByTestId('work-item-plan-cta-dropdown')).queryByTestId(
            'base-dropdown-toggle',
          ),
        );
        dropdownToggle.click();
        await waitForElement(() =>
          dropdownToggle.getAttribute('aria-expanded') === 'true' ? dropdownToggle : null,
        );
        await waitAndClick(() =>
          withinDrawer().queryByTestId('work-item-plan-cta-create-manually'),
        );
      });

      it('turns on planning and opens the workplan editor on the work item page', async () => {
        await waitForElement(findInlineRow);

        expect(findPlanCta()).toBe(null);
        await waitForAssertion(() => {
          expect(visitUrlSpy).toHaveBeenCalledWith(
            expect.stringMatching(/\?show=workplan&workplan_state=edit$/),
          );
        });
      });
    });

    describe('when the user selects Implement from the Plan CTA', () => {
      beforeEach(async () => {
        server.use(
          http.post(/\/api\/v4\/ai\/duo_workflows\/workflows$/, async ({ request }) => {
            captureRequest('startDuoWorkflow', request, await request.clone().json());
            return HttpResponse.json({ id: 7 });
          }),
        );
        await waitForElement(findPlanCta);
        const dropdownToggle = await waitForElement(() =>
          within(withinDrawer().queryByTestId('work-item-plan-cta-dropdown')).queryByTestId(
            'base-dropdown-toggle',
          ),
        );
        dropdownToggle.click();
        await waitForElement(() =>
          dropdownToggle.getAttribute('aria-expanded') === 'true' ? dropdownToggle : null,
        );
        await waitAndClick(
          () =>
            withinDrawer().queryByTestId('work-item-plan-cta-implement')?.querySelector('button') ??
            null,
        );
      });

      it('starts the Developer flow for the work item and leaves planning off', async () => {
        await waitForAssertion(() => {
          expect(lastRequestVariables('startDuoWorkflow')).toMatchObject({
            workflow_definition: 'developer/v1',
            source: 'work_item_to_merge_request',
            goal: expect.stringMatching(/^@\S* assigned you to solve the following issue: /),
          });
        });

        expect(findPlanCta()).not.toBe(null);
        expect(findInlineRow()).toBe(null);
      });
    });
  });

  describe('when the work item has an agent plan widget with AI disabled and no update permission', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItem).withAgentPlanAiDisabledNoUpdate();
      await mountAndOpenWorkItem();
    });

    it('renders neither the workplan nor the Plan CTA', async () => {
      await waitForElement(findWorkItemDetail);

      expect(findInlineRow()).toBe(null);
      expect(findPlanCta()).toBe(null);
    });
  });

  describe('when the work item has an agent plan widget', () => {
    describe('when the user has update permission', () => {
      describe('when there is no saved workplan', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withEmptyAgentPlan();
          await mountAndOpenWorkItem();
        });

        it('shows the workplan inline row with a create action', async () => {
          await waitForElement(findInlineRow);
          // The create action appears once the standalone agent-plan query settles.
          await waitForElement(findCreateWorkplanDropdown);

          expect(getText(findInlineRow())).toContain('Not yet created');
        });

        describe('when the user opens the panel through the create dropdown', () => {
          beforeEach(async () => {
            const dropdownToggle = await waitForElement(() =>
              within(findCreateWorkplanDropdown()).queryByTestId('base-dropdown-toggle'),
            );
            dropdownToggle.click();
            // Opening the dropdown can re-render its items, so a click before that lands on a stale item.
            await waitForElement(() =>
              dropdownToggle.getAttribute('aria-expanded') === 'true' ? dropdownToggle : null,
            );
            await waitAndClick(() => withinDrawer().queryByTestId('create-workplan-dropdown-item'));
          });

          it('opens the panel directly in edit mode, skipping the empty state', async () => {
            await waitForElement(findWorkplanEditor);

            expect(findWorkplanEditor()).not.toBe(null);
            expect(findEmptyState()).toBe(null);
            expect(viewEvents()).toHaveLength(0);
          });
        });
      });

      describe('when there is a saved workplan', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withAgentPlan();
          setQueryVariant(workItemAgentPlan).withContent();
          await mountAndOpenWorkItem();
        });

        it('shows the workplan inline row ready to review', async () => {
          await waitForElement(findInlineRow);
          // "Ready for review" appears once the standalone agent-plan query resolves with content.
          await waitForElement(findOpenButton);

          expect(getText(findInlineRow())).toContain('Ready for review');
          expect(viewEvents()).toHaveLength(0);
        });

        describe('when the user opens the panel', () => {
          beforeEach(async () => {
            await waitForElement(findInlineRow);
            await waitAndClick(findOpenButton);
          });

          it('renders the saved workplan content', async () => {
            await waitForElement(findRenderedPlan);

            expect(getText(findRenderedPlan())).toContain('Existing workplan content');
            expect(viewEvents()).toHaveLength(1);
          });
        });
      });

      describe('when the workplan is scored and the score flag is on', () => {
        beforeEach(async () => {
          setQueryVariant(namespaceWorkItem).withAgentPlan();
          setQueryVariant(workItemAgentPlan).withContentAndScore();
          await mountAndOpenWorkItem({ glFeatures: { workplanScore: true } });
          await waitForElement(findInlineRow);
          await waitAndClick(findOpenButton);
        });

        it('renders the score alongside the plan', async () => {
          await waitForElement(findMediumReadiness);

          expect(findMediumReadiness()).not.toBe(null);
        });

        describe('when the content is edited and saved', () => {
          let baseline;

          beforeEach(async () => {
            await waitForElement(findMediumReadiness);

            await waitAndClick(findPanelEditButton);
            await waitForElement(findWorkplanEditor);
            await waitAndSetValue(findEditorTextarea, 'Updated workplan content');

            baseline = snapshotRequests();
            await waitAndClick(findSaveButton);

            await waitForAssertion(() => {
              expect(getText(findRenderedPlan())).toContain('Updated workplan content');
            });
          });

          it('renders the updated content', () => {
            expect(getText(findRenderedPlan())).toContain('Updated workplan content');
            expect(viewEvents()).toHaveLength(1);
          });

          it('keeps the readiness score', () => {
            expect(findMediumReadiness()).not.toBe(null);
          });

          it('serves the update from the cache without refetching the plan', () => {
            // Forbidding the refetch is what proves the surviving score came from the
            // cache write rather than the server re-supplying it.
            expectGraphQLCalls(baseline, {
              expect: ['updateWorkItemAgentPlan'],
              forbid: ['workItemAgentPlan', ...FORBIDDEN_LIST_REFETCHES],
            });
          });
        });
      });
    });

    describe('when the run is paused on a Duo question', () => {
      beforeEach(async () => {
        setQueryVariant(namespaceWorkItem).withAgentPlan();
        setQueryVariant(workItemAgentPlan).awaitingOneOpenQuestion();
        setQueryVariant(workItemNotesByIid).duoQuestion();
        await mountAndOpenWorkItem();
        await waitForAssertion(() => {
          expect(getText(findInlineRow())).toContain('Awaiting input (1 question)');
        });
      });

      // The sticky header reads the plan the widget fetched, so this proves the two agree.
      it('shows the open questions count in the sticky header', () => {
        expect(getText(withinDrawer().getByTestId('sticky-header-open-questions-count'))).toBe('1');
      });

      describe('when the question is answered from its card', () => {
        let baseline;

        beforeEach(async () => {
          setQueryVariant(workItemAgentPlan).awaitingAllQuestionsAnswered();
          baseline = snapshotRequests();

          await waitAndClick(findDuoQuestionOption);
          await waitForAssertion(() => {
            expect(getText(findInlineRow())).toContain('All questions resolved');
          });
        });

        it('refetches the Workplan after posting the answer and resolving the thread', () => {
          expectGraphQLCalls(baseline, {
            expect: [
              'createWorkItemNote',
              'toggleWorkItemNoteResolveDiscussion',
              'workItemAgentPlan',
            ],
            forbid: FORBIDDEN_LIST_REFETCHES,
          });
        });

        it('resolves the decision GitLab Duo opened for the question with the picked option', async () => {
          const [decision] =
            workItemDecisionsFixture.data.namespace.workItem.features.decisionLog.decisions.nodes;
          // The card's first option, which the outer `beforeEach` clicks.
          const pickedOption = decision.options.nodes.find(
            ({ content }) => content === 'Reject immediately',
          );

          await waitForAssertion(() => {
            expectGraphQLCalls(baseline, {
              expect: ['workItemDecisions', 'workItemDecisionResolve'],
              forbid: FORBIDDEN_LIST_REFETCHES,
            });
          });

          expect(lastRequestVariables('workItemDecisionResolve').input).toMatchObject({
            id: decision.id,
            selectedOptionIds: [pickedOption.id],
            resolutionRationale: null,
          });
        });

        it('removes the open questions from the sticky header', async () => {
          await waitForAssertion(() => {
            expect(withinDrawer().queryByTestId('sticky-header-workplan-questions')).toBeNull();
          });
        });
      });
    });

    describe('when the user has no update permission', () => {
      beforeEach(async () => {
        setQueryVariant(namespaceWorkItem).withEmptyAgentPlanNoUpdate();
        await mountAndOpenWorkItem();
      });

      it('shows the workplan inline row without a create action', async () => {
        await waitForElement(findInlineRow);

        expect(getText(findInlineRow())).toContain('No workplan');
        expect(findOpenButton()).toBe(null);
        expect(findCreateWorkplanDropdown()).toBe(null);
      });
    });
  });
});
