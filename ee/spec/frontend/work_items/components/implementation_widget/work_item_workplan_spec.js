import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import WorkItemWorkplan from 'ee/work_items/components/implementation_widget/work_item_workplan.vue';
import WorkplanInlineRow from 'ee/work_items/components/implementation_widget/workplan_inline_row.vue';
import WorkplanPanel from 'ee/work_items/components/implementation_widget/workplan_panel.vue';
import { eventHub, REFETCH_SESSIONS, SHOW_SESSION } from 'ee/ai/events/panel';
import updateWorkItemAgentPlanMutation from 'ee/work_items/graphql/update_work_item_agent_plan.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import workItemResumeWorkplanMutation from 'ee/work_items/graphql/work_item_resume_workplan.mutation.graphql';
import workplanFlowAvailabilityQuery from 'ee/work_items/graphql/workplan_flow_availability.query.graphql';
import { writeAgentPlanToCache } from 'ee/work_items/graphql/cache_utils';
import {
  FLOW_ACTION_TIMEOUT_MS,
  TERMINAL_STATUS_CONFIRM_MS,
} from 'ee/work_items/components/implementation_widget/constants';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import * as urlUtility from '~/lib/utils/url_utility';
import { getDraft, updateDraft, clearDraft } from '~/lib/utils/autosave';
import {
  buildAgentPlanWidgetMock,
  buildWorkplanFlowAvailabilityResponse,
  buildWorkplanFlowMutationResponse,
  workItemResponseFactory,
} from 'ee_jest/work_items/mock_data';

jest.mock('ee/work_items/graphql/cache_utils');
jest.mock('~/lib/utils/autosave');
jest.mock('~/alert');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal', () => ({
  confirmAction: jest.fn(),
}));

Vue.use(VueApollo);

const QUESTIONS = {
  __typename: 'WorkItemAgentPlanQuestionConnection',
  nodes: [
    { __typename: 'WorkItemAgentPlanQuestion', noteId: 'gid://gitlab/Note/1', answered: false },
  ],
};
const ANSWERED_QUESTIONS = {
  __typename: 'WorkItemAgentPlanQuestionConnection',
  nodes: [
    { __typename: 'WorkItemAgentPlanQuestion', noteId: 'gid://gitlab/Note/1', answered: true },
  ],
};
const NO_QUESTIONS = { __typename: 'WorkItemAgentPlanQuestionConnection', nodes: [] };

describe('WorkItemWorkplan component (orchestrator)', () => {
  let wrapper;
  let apolloProvider;
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const mockWorkItemId = 'gid://gitlab/WorkItem/1';
  const mockWorkItemWebUrl = 'http://gdk.test/gitlab-org/gitlab/-/issues/1';
  const planStorageKey = `work-plan-draft-${mockWorkItemId}`;

  const buildWorkItem = ({ workItemId = mockWorkItemId, workItemType = 'Epic' } = {}) => {
    const base = workItemResponseFactory({ id: workItemId }).data.workItem;
    return {
      ...base,
      workItemType: { ...base.workItemType, name: workItemType },
    };
  };

  const paragraphHtml = (text) => {
    const p = document.createElement('p');
    p.textContent = text;
    return p.outerHTML;
  };

  const generateHandlerFor = (options) =>
    jest
      .fn()
      .mockResolvedValue(buildWorkplanFlowMutationResponse('workItemGenerateWorkplan', options));

  const resumeHandlerFor = (options) =>
    jest
      .fn()
      .mockResolvedValue(buildWorkplanFlowMutationResponse('workItemResumeWorkplan', options));

  const buildWorkplan = ({
    content = '',
    contentHtml = null,
    aiPlanningEnabled = true,
    readinessScore = null,
    generationStatus = null,
    openQuestionsCount = null,
    questions = null,
  } = {}) =>
    buildAgentPlanWidgetMock({
      content,
      contentHtml: contentHtml ?? (content ? paragraphHtml(content) : ''),
      aiPlanningEnabled,
      readinessScore,
      generationStatus,
      openQuestionsCount,
      questions,
    });

  const successMutationHandler = jest.fn().mockImplementation(({ input, useWorkItemFeatures }) =>
    Promise.resolve({
      data: {
        workItemUpdate: {
          __typename: 'WorkItemUpdatePayload',
          workItem: {
            __typename: 'WorkItem',
            id: mockWorkItemId,
            iid: '1',
            ...(useWorkItemFeatures
              ? {
                  features: {
                    __typename: 'WorkItemFeatures',
                    agentPlan: buildWorkplan({ content: input.agentPlanWidget.content }),
                  },
                }
              : { widgets: [buildWorkplan({ content: input.agentPlanWidget.content })] }),
          },
          errors: [],
        },
      },
    }),
  );

  const pushWorkplan = (options) => wrapper.setProps({ workplan: buildWorkplan(options) });

  const pushWorkplanContent = (content) => pushWorkplan({ content });

  const createComponent = ({
    canUpdate = true,
    content = '',
    workplan = buildWorkplan({ content }),
    isLoading = false,
    workItem = buildWorkItem(),
    workItemWebUrl = mockWorkItemWebUrl,
    isInDrawer = false,
    isPanelOpen = false,
    isWorkItemClosed = false,
    mutationHandler = successMutationHandler,
    generateHandler = generateHandlerFor(),
    resumeHandler = resumeHandlerFor(),
    availabilityHandler = jest.fn().mockResolvedValue(buildWorkplanFlowAvailabilityResponse()),
    duoRemoteFlowsAvailability = false,
    fullPath = 'group/project',
    glFeatures = {},
  } = {}) => {
    apolloProvider = createMockApollo([
      [updateWorkItemAgentPlanMutation, mutationHandler],
      [workItemGenerateWorkplanMutation, generateHandler],
      [workItemResumeWorkplanMutation, resumeHandler],
      [workplanFlowAvailabilityQuery, availabilityHandler],
    ]);
    wrapper = shallowMountExtended(WorkItemWorkplan, {
      apolloProvider,
      propsData: {
        workItem,
        canUpdate,
        workItemWebUrl,
        isInDrawer,
        isPanelOpen,
        isWorkItemClosed,
        workplan,
        isLoading,
      },
      provide: { fullPath, duoRemoteFlowsAvailability, glFeatures },
    });
  };

  const findInlineRow = () => wrapper.findComponent(WorkplanInlineRow);
  const findPanel = () => wrapper.findComponent(WorkplanPanel);

  const setSearch = (search) => {
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { ...window.location, search },
    });
  };

  const triggerPopstate = () => window.dispatchEvent(new PopStateEvent('popstate'));

  beforeEach(() => {
    getDraft.mockReturnValue(null);
    successMutationHandler.mockClear();
    confirmAction.mockReset();
  });

  describe('workplan view tracking', () => {
    let trackEventSpy;

    beforeEach(() => {
      ({ trackEventSpy } = bindInternalEventDocument());
      setSearch('');
    });

    afterEach(() => {
      setSearch('');
    });

    describe.each([
      ['closed panel', { isPanelOpen: false }],
      ['loading plan', { isLoading: true }],
      ['empty plan', { content: '' }],
      ['whitespace-only plan', { content: '   ' }],
      [
        'missing rendered content',
        { workplan: buildWorkplan({ content: 'plan', contentHtml: '' }) },
      ],
      [
        'active generation',
        { workplan: buildWorkplan({ content: 'plan', generationStatus: 'GENERATING' }) },
      ],
    ])('with %s', (description, props) => {
      beforeEach(async () => {
        createComponent({ content: 'plan', isPanelOpen: true, ...props });
        await waitForPromises();
      });

      it('does not track a view', () => {
        expect(trackEventSpy).not.toHaveBeenCalled();
      });
    });

    describe('when a saved plan is displayed', () => {
      beforeEach(async () => {
        createComponent({ content: 'plan', isPanelOpen: true });
        await waitForPromises();
      });

      it('tracks one UI view', () => {
        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith(
          'view_work_item_workplan',
          { work_item_id: 1 },
          undefined,
        );
      });

      it('does not track content updates or loading transitions again', async () => {
        await pushWorkplanContent('updated plan');
        await wrapper.setProps({ isLoading: true });
        await wrapper.setProps({ isLoading: false });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });

      it('does not track an edit and save cycle again', async () => {
        findPanel().vm.$emit('start-edit');
        await nextTick();
        findPanel().vm.$emit('save', 'updated plan');
        await waitForPromises();

        expect(findPanel().props('isEditing')).toBe(false);
        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });

      it('tracks another view after closing and reopening', async () => {
        await wrapper.setProps({ isPanelOpen: false });
        await wrapper.setProps({ isPanelOpen: true });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(2);
      });

      it('tracks a view for another work item', async () => {
        await wrapper.setProps({
          workItem: buildWorkItem({ workItemId: 'gid://gitlab/WorkItem/2' }),
          workplan: buildWorkplan({ content: 'another plan' }),
        });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(2);
        expect(trackEventSpy).toHaveBeenLastCalledWith(
          'view_work_item_workplan',
          { work_item_id: 2 },
          undefined,
        );
      });
    });

    describe('when opening a direct link', () => {
      beforeEach(async () => {
        setSearch('?show=workplan');
        createComponent({ content: 'plan', isPanelOpen: true, isLoading: true });
        await waitForPromises();
      });

      it('waits for the plan to finish loading', async () => {
        expect(trackEventSpy).not.toHaveBeenCalled();

        await wrapper.setProps({ isLoading: false });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });

    describe('when opening a direct edit link', () => {
      beforeEach(async () => {
        setSearch('?show=workplan&workplan_state=edit');
        createComponent({ content: 'plan', isPanelOpen: true });
        await waitForPromises();
      });

      it('does not track an editor-only visit', () => {
        expect(findPanel().props('isEditing')).toBe(true);
        expect(trackEventSpy).not.toHaveBeenCalled();
      });

      it('tracks the first display after leaving the editor', async () => {
        findPanel().vm.$emit('cancel-edit');
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });

    describe('when content arrives in an empty open panel', () => {
      beforeEach(async () => {
        createComponent({ isPanelOpen: true });
        await waitForPromises();
      });

      it('tracks only after content is displayed', async () => {
        expect(trackEventSpy).not.toHaveBeenCalled();
        await pushWorkplanContent('generated plan');
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });

    describe('when a generated plan lands while the panel is closed', () => {
      beforeEach(async () => {
        createComponent({
          workplan: buildWorkplan({ generationStatus: 'GENERATING' }),
        });
        await waitForPromises();
      });

      it('tracks once the panel is opened', async () => {
        await pushWorkplan({ content: 'generated plan', generationStatus: 'GENERATING' });
        expect(trackEventSpy).not.toHaveBeenCalled();

        await wrapper.setProps({ isPanelOpen: true });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });

    describe('when browser navigation opens the panel', () => {
      beforeEach(() => {
        createComponent({ content: 'plan' });
      });

      it('tracks after the requested panel is displayed', async () => {
        setSearch('?show=workplan');
        triggerPopstate();
        expect(wrapper.emitted('request-panel')).toContainEqual(['workplan']);
        expect(trackEventSpy).not.toHaveBeenCalled();

        await wrapper.setProps({ isPanelOpen: true });
        await waitForPromises();

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('workplan action tracking', () => {
    it.each`
      event           | findSource       | label           | property
      ${'generate'}   | ${findInlineRow} | ${'generate'}   | ${'inline_row'}
      ${'retry'}      | ${findInlineRow} | ${'retry'}      | ${'inline_row'}
      ${'continue'}   | ${findInlineRow} | ${'continue'}   | ${'inline_row'}
      ${'generate'}   | ${findPanel}     | ${'generate'}   | ${'panel'}
      ${'regenerate'} | ${findPanel}     | ${'regenerate'} | ${'panel'}
    `('tracks $label from $property once', async ({ event, findSource, label, property }) => {
      const { trackEventSpy } = bindInternalEventDocument();
      createComponent({ generateHandler: generateHandlerFor(), resumeHandler: resumeHandlerFor() });

      findSource().vm.$emit(event);
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_work_item_workplan_action',
        { label, property },
        undefined,
      );
    });
  });

  describe('inline row wiring', () => {
    describe('when generation is unavailable', () => {
      let generateHandler;
      let resumeHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        resumeHandler = resumeHandlerFor();
        createComponent({
          generateHandler,
          resumeHandler,
          availabilityHandler: jest
            .fn()
            .mockResolvedValue(
              buildWorkplanFlowAvailabilityResponse({ remoteFlowsEnabled: false }),
            ),
        });
        await waitForPromises();
      });

      it.each(['generate', 'retry', 'continue'])('blocks the %s action', async (action) => {
        findInlineRow().vm.$emit(action);
        await waitForPromises();

        expect(generateHandler).not.toHaveBeenCalled();
        expect(resumeHandler).not.toHaveBeenCalled();
        expect(findInlineRow().props('generationDisabledReason')).toBe(
          "Workplan generation isn't turned on for this project.",
        );
      });

      it('blocks Regenerate without closing the panel', async () => {
        findPanel().vm.$emit('regenerate');
        await waitForPromises();

        expect(generateHandler).not.toHaveBeenCalled();
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });

      it('passes the reason to the panel', () => {
        expect(findPanel().props('generationDisabledReason')).toBe(
          "Workplan generation isn't turned on for this project.",
        );
      });
    });

    describe('when generation is available', () => {
      let availabilityHandler;

      beforeEach(async () => {
        availabilityHandler = jest.fn().mockResolvedValue(buildWorkplanFlowAvailabilityResponse());
        createComponent({ availabilityHandler });
        await waitForPromises();
      });

      it('queries availability for the work item project', () => {
        expect(availabilityHandler).toHaveBeenCalledWith({ fullPath: 'test-project-path' });
      });

      it('passes no reason to the inline row', () => {
        expect(findInlineRow().props('generationDisabledReason')).toBe('');
      });
    });

    describe('when the availability query fails', () => {
      beforeEach(async () => {
        createComponent({
          availabilityHandler: jest.fn().mockRejectedValue(new Error('Network error')),
        });
        await waitForPromises();
      });

      it('keeps generation enabled', () => {
        expect(findInlineRow().props('generationDisabledReason')).toBe('');
      });
    });

    describe('while availability is loading', () => {
      beforeEach(() => {
        createComponent({ availabilityHandler: jest.fn().mockReturnValue(new Promise(() => {})) });
      });

      it('keeps generation enabled', () => {
        expect(findInlineRow().props('generationDisabledReason')).toBe('');
      });
    });

    describe('when there is no saved content', () => {
      beforeEach(() => {
        createComponent({ content: '' });
      });

      it('passes hasContent=false', () => {
        expect(findInlineRow().props('hasContent')).toBe(false);
      });
    });

    describe('when content is set on the work item', () => {
      beforeEach(async () => {
        createComponent({ content: 'some plan' });
        await waitForPromises();
      });

      it('passes hasContent=true', () => {
        expect(findInlineRow().props('hasContent')).toBe(true);
      });
    });

    describe('when canUpdate is false', () => {
      beforeEach(() => {
        createComponent({ canUpdate: false });
      });

      it('forwards canUpdate to the inline row', () => {
        expect(findInlineRow().props('canUpdate')).toBe(false);
      });
    });

    describe.each`
      scenario                             | openQuestionsCount | questions             | hasQuestions
      ${'the plan reports open questions'} | ${1}               | ${QUESTIONS}          | ${true}
      ${'every question is answered'}      | ${0}               | ${ANSWERED_QUESTIONS} | ${true}
      ${'the run asked nothing'}           | ${0}               | ${NO_QUESTIONS}       | ${false}
      ${'the count does not apply'}        | ${null}            | ${null}               | ${false}
    `('when $scenario', ({ openQuestionsCount, questions, hasQuestions }) => {
      beforeEach(() => {
        createComponent({
          workplan: buildWorkplan({
            generationStatus: 'NEEDS_INPUT',
            openQuestionsCount,
            questions,
          }),
        });
      });

      it('passes the open questions count and the questions asked to the inline row', () => {
        expect(findInlineRow().props('generation')).toMatchObject({
          openQuestionsCount,
          hasQuestions,
          questions: questions?.nodes ?? [],
        });
      });
    });

    describe('when the plan has not loaded yet', () => {
      beforeEach(() => {
        createComponent({ workplan: null });
      });

      it('passes no count and no questions to the inline row', () => {
        expect(findInlineRow().props('generation')).toMatchObject({
          openQuestionsCount: undefined,
          hasQuestions: false,
        });
      });
    });
  });

  describe.each([true, false])('when isWorkItemClosed is %s', (isWorkItemClosed) => {
    beforeEach(() => {
      createComponent({ isWorkItemClosed });
    });

    it('forwards isWorkItemClosed to the inline row and the panel', () => {
      expect(findInlineRow().props('isWorkItemClosed')).toBe(isWorkItemClosed);
      expect(findPanel().props('isWorkItemClosed')).toBe(isWorkItemClosed);
    });
  });

  describe('panel wiring', () => {
    describe('when the panel is open', () => {
      beforeEach(() => {
        createComponent({ isPanelOpen: true });
      });

      it('passes isPanelOpen down as the panel open prop', () => {
        expect(findPanel().props('open')).toBe(true);
      });
    });

    describe('when the parent provides saved content', () => {
      beforeEach(async () => {
        createComponent({ content: 'plan via widgets' });
        await waitForPromises();
      });

      it('passes the queried content as savedContent', () => {
        expect(findPanel().props('savedContent')).toBe('plan via widgets');
      });

      it('passes the queried contentHtml as savedContentHtml', () => {
        expect(findPanel().props('savedContentHtml')).toBe(paragraphHtml('plan via widgets'));
      });
    });

    describe('cache write on save', () => {
      const lastCacheWrite = () => writeAgentPlanToCache.mock.calls.at(-1)[0];

      const save = async (options) => {
        createComponent(options);
        await findPanel().vm.$emit('save', 'new plan');
        await waitForPromises();
      };

      describe('when workplanScore is enabled', () => {
        beforeEach(() =>
          save({
            workplan: buildWorkplan({
              content: 'old plan',
              readinessScore: 72,
              openQuestionsCount: 3,
              questions: QUESTIONS,
            }),
            glFeatures: { workplanScore: true },
          }),
        );

        it('writes the new content and carries the existing plan values forward', () => {
          expect(lastCacheWrite()).toMatchObject({
            openQuestionsCount: 3,
            questions: QUESTIONS,
            workItemId: mockWorkItemId,
            workItemIid: '1',
            content: 'new plan',
            contentHtml: '<p>new plan</p>',
            aiPlanningEnabled: true,
            readinessScore: 72,
            includeReadinessScore: true,
          });
        });
      });

      describe('when workplanScore is disabled', () => {
        beforeEach(() => save({ workplan: buildWorkplan({ content: 'old plan' }) }));

        it('leaves the readiness score out of the write', () => {
          expect(lastCacheWrite()).toMatchObject({
            content: 'new plan',
            contentHtml: '<p>new plan</p>',
            readinessScore: null,
            includeReadinessScore: false,
          });
        });
      });

      describe('when workItemFeaturesField is enabled', () => {
        beforeEach(() =>
          save({
            workplan: buildWorkplan({ content: 'old plan' }),
            glFeatures: { workItemFeaturesField: true },
          }),
        );

        it('writes the rendered HTML returned through features', () => {
          expect(lastCacheWrite()).toMatchObject({
            content: 'new plan',
            contentHtml: '<p>new plan</p>',
            aiPlanningEnabled: true,
            useWorkItemFeatures: true,
          });
        });
      });
    });

    describe('when rendered with defaults', () => {
      beforeEach(() => {
        createComponent({ canUpdate: true });
      });

      it('forwards canUpdate to the panel', () => {
        expect(findPanel().props('canUpdate')).toBe(true);
      });
    });
  });

  describe('openPanel', () => {
    describe('when the inline row opens', () => {
      beforeEach(async () => {
        createComponent({ content: 'existing' });
        await findInlineRow().vm.$emit('open');
      });

      it('emits request-panel with the workplan key', () => {
        expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
      });
    });

    describe('when opening with no content and the user can update', () => {
      beforeEach(async () => {
        createComponent({ content: '', canUpdate: true });
        await findInlineRow().vm.$emit('open');
      });

      it('opens in view mode (empty state)', () => {
        expect(findPanel().props('isEditing')).toBe(false);
      });

      describe('when the panel empty state requests edit ("Create manually")', () => {
        beforeEach(async () => {
          await findPanel().vm.$emit('start-edit');
        });

        it('enters edit mode', () => {
          expect(findPanel().props('isEditing')).toBe(true);
        });
      });
    });

    describe('when opening with existing content', () => {
      beforeEach(async () => {
        createComponent({ content: 'existing', canUpdate: true });
        await findInlineRow().vm.$emit('open');
      });

      it('stays in view mode', () => {
        expect(findPanel().props('isEditing')).toBe(false);
      });
    });

    describe('when the user cannot update', () => {
      beforeEach(async () => {
        createComponent({ content: '', canUpdate: false });
        await findInlineRow().vm.$emit('open');
      });

      it('stays in view mode', () => {
        expect(findPanel().props('isEditing')).toBe(false);
      });
    });

    describe('when a leftover draft exists', () => {
      beforeEach(async () => {
        getDraft.mockImplementation((key) => (key === planStorageKey ? 'half-typed' : null));
        createComponent({ content: 'existing', canUpdate: true });
        await findInlineRow().vm.$emit('open');
      });

      it('opens in view mode (View workplan must not force edit)', () => {
        expect(findPanel().props('isEditing')).toBe(false);
      });
    });

    describe('when the inline row re-emits open while already open (toggle)', () => {
      let updateHistorySpy;
      let originalSearch;

      beforeEach(async () => {
        originalSearch = window.location.search;
        setSearch('?show=workplan');
        updateHistorySpy = jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
        createComponent({ content: 'existing', isPanelOpen: true });
        await findInlineRow().vm.$emit('open');
      });

      afterEach(() => {
        setSearch(originalSearch);
        updateHistorySpy.mockRestore();
      });

      it('closes the panel', () => {
        expect(wrapper.emitted('request-panel')).toEqual([[null]]);
      });

      it('strips the workplan params from the URL', () => {
        expect(updateHistorySpy).toHaveBeenCalledTimes(1);
        expect(updateHistorySpy.mock.calls[0][0].url).not.toMatch(/show=/);
      });
    });

    describe('when the inline row emits "create-manually"', () => {
      beforeEach(async () => {
        createComponent({ content: '', canUpdate: true });
        await findInlineRow().vm.$emit('create-manually');
      });

      it('opens the panel directly in edit mode', () => {
        expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
        expect(findPanel().props('isEditing')).toBe(true);
      });
    });

    describe('when the inline row emits "create-manually" after generation failed', () => {
      beforeEach(async () => {
        createComponent({
          workplan: buildWorkplan({ generationStatus: 'FAILED' }),
          canUpdate: true,
        });
        await findInlineRow().vm.$emit('create-manually');
      });

      it('opens the failed workplan directly in edit mode', () => {
        expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
        expect(findPanel().props('isEditing')).toBe(true);
      });

      it('closes without saving when editing is canceled', () => {
        findPanel().vm.$emit('cancel-edit');

        expect(wrapper.emitted('request-panel')).toEqual([['workplan'], [null]]);
        expect(successMutationHandler).not.toHaveBeenCalled();
        expect(findInlineRow().props('hasContent')).toBe(false);
      });
    });

    describe('when rendered inside a drawer', () => {
      let visitUrlSpy;

      beforeEach(() => {
        visitUrlSpy = jest.spyOn(urlUtility, 'visitUrl').mockImplementation(() => {});
        createComponent({
          isInDrawer: true,
          workItemWebUrl: '/group/project/-/work_items/42',
        });
      });

      afterEach(() => {
        visitUrlSpy.mockRestore();
      });

      describe('when the inline row opens', () => {
        beforeEach(async () => {
          await findInlineRow().vm.$emit('open');
        });

        it('navigates to the full work-item page with ?show=workplan', () => {
          expect(visitUrlSpy).toHaveBeenCalledWith('/group/project/-/work_items/42?show=workplan');
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });

      describe('when creating manually', () => {
        beforeEach(async () => {
          await findInlineRow().vm.$emit('create-manually');
        });

        it('navigates to the full page with the edit deep-link so the state survives the jump', () => {
          expect(visitUrlSpy).toHaveBeenCalledWith(
            '/group/project/-/work_items/42?show=workplan&workplan_state=edit',
          );
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });
    });
  });

  describe('Duo "Generate" path', () => {
    describe('when Duo generates a plan', () => {
      let updateHistorySpy;

      beforeEach(async () => {
        updateHistorySpy = jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
        createComponent({ content: '', canUpdate: true });
        await waitForPromises();
      });

      afterEach(() => {
        updateHistorySpy.mockRestore();
      });

      describe('when the generated plan is saved', () => {
        beforeEach(async () => {
          pushWorkplanContent('generated plan');
          await waitForPromises();
        });

        it('leaves the panel closed and the URL untouched', () => {
          expect(wrapper.emitted('request-panel')).toBeUndefined();
          expect(updateHistorySpy).not.toHaveBeenCalled();
        });

        it('tells the inline row the plan now exists', () => {
          expect(findInlineRow().props('hasContent')).toBe(true);
        });
      });
    });
  });

  describe('closePanel', () => {
    describe('when the panel emits close', () => {
      let updateHistorySpy;
      let originalSearch;

      beforeEach(async () => {
        originalSearch = window.location.search;
        setSearch('?show=workplan&workplan_state=edit');
        updateHistorySpy = jest.spyOn(urlUtility, 'updateHistory').mockImplementation(() => {});
        createComponent({ isPanelOpen: true });
        await findPanel().vm.$emit('close');
      });

      afterEach(() => {
        setSearch(originalSearch);
        updateHistorySpy.mockRestore();
      });

      it('emits request-panel null', () => {
        expect(wrapper.emitted('request-panel')).toEqual([[null]]);
      });

      it('strips both workplan params from the URL', () => {
        expect(updateHistorySpy).toHaveBeenCalledTimes(1);
        expect(updateHistorySpy.mock.calls[0][0].url).not.toMatch(/show=/);
        expect(updateHistorySpy.mock.calls[0][0].url).not.toMatch(/workplan_state/);
      });

      it('resets editing so a later reopen starts in view mode', () => {
        expect(findPanel().props('isEditing')).toBe(false);
      });
    });
  });

  describe('URL sync', () => {
    let originalSearch;

    beforeEach(() => {
      originalSearch = window.location.search;
    });

    afterEach(() => {
      setSearch(originalSearch);
    });

    describe('on load', () => {
      describe('when ?show=workplan is present', () => {
        beforeEach(() => {
          setSearch('?show=workplan');
          createComponent({ isPanelOpen: false });
        });

        it('opens the panel', () => {
          expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
        });

        it('opens in view mode', () => {
          expect(findPanel().props('isEditing')).toBe(false);
        });
      });

      describe('when the edit deep-link is present', () => {
        beforeEach(() => {
          setSearch('?show=workplan&workplan_state=edit');
          createComponent({ isPanelOpen: false });
        });

        it('opens the panel directly in edit mode', () => {
          expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
          expect(findPanel().props('isEditing')).toBe(true);
        });
      });

      describe('when the param is absent', () => {
        beforeEach(() => {
          setSearch('');
          createComponent({ isPanelOpen: false });
        });

        it('does not open the panel', () => {
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });
    });

    describe('on popstate', () => {
      describe('when the param is (re)added and the panel is closed', () => {
        beforeEach(() => {
          setSearch('');
          createComponent({ isPanelOpen: false });

          setSearch('?show=workplan');
          triggerPopstate();
        });

        it('re-opens the panel', () => {
          expect(wrapper.emitted('request-panel')).toEqual([['workplan']]);
        });
      });

      describe('when the param is removed and the panel is open', () => {
        beforeEach(() => {
          setSearch('?show=workplan');
          createComponent({ isPanelOpen: true });

          setSearch('');
          triggerPopstate();
        });

        it('closes the panel', () => {
          expect(wrapper.emitted('request-panel')).toEqual([[null]]);
        });
      });

      describe('when the panel state already matches the URL', () => {
        beforeEach(() => {
          setSearch('?show=workplan');
          createComponent({ isPanelOpen: true });

          triggerPopstate();
        });

        it('does not re-emit', () => {
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });

      describe('when rendered inside a drawer', () => {
        beforeEach(() => {
          setSearch('?show=workplan');
          createComponent({ isInDrawer: true, isPanelOpen: false });

          triggerPopstate();
        });

        it('ignores popstate', () => {
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });

      describe('when the component has been destroyed', () => {
        beforeEach(() => {
          setSearch('');
          createComponent({ isPanelOpen: false });
          wrapper.destroy();

          setSearch('?show=workplan');
          triggerPopstate();
        });

        it('stops listening to popstate', () => {
          expect(wrapper.emitted('request-panel')).toBeUndefined();
        });
      });
    });
  });

  describe('while the parent reports the agent plan as loading', () => {
    beforeEach(() => {
      createComponent({ isLoading: true, workplan: null });
    });

    it('marks the inline row and panel as loading', () => {
      expect(findInlineRow().props('isLoading')).toBe(true);
      expect(findPanel().props('isLoading')).toBe(true);
    });

    it('reports no saved content until the plan arrives', () => {
      expect(findInlineRow().props('hasContent')).toBe(false);
    });
  });

  describe('handleSave', () => {
    describe('when the save succeeds', () => {
      beforeEach(() => {
        createComponent({ isPanelOpen: true });
      });

      describe('with fresh content', () => {
        beforeEach(async () => {
          await findPanel().vm.$emit('save', 'fresh plan');
          await waitForPromises();
        });

        it('sends the new content to the mutation', () => {
          expect(successMutationHandler).toHaveBeenCalledWith(
            expect.objectContaining({
              input: { id: mockWorkItemId, agentPlanWidget: { content: 'fresh plan' } },
            }),
          );
        });

        it('writes the content and contentHtml from the mutation response to the cache', () => {
          expect(writeAgentPlanToCache).toHaveBeenCalledWith(
            expect.objectContaining({
              content: 'fresh plan',
              contentHtml: paragraphHtml('fresh plan'),
            }),
          );
        });
      });

      describe('with persisted content', () => {
        beforeEach(async () => {
          await findPanel().vm.$emit('save', 'persisted');
          await waitForPromises();
        });

        it('clears the draft on successful save', () => {
          expect(clearDraft).toHaveBeenCalledWith(planStorageKey);
        });
      });
    });

    describe('when the save fails', () => {
      const failingHandler = jest
        .fn()
        .mockResolvedValue({ data: { workItemUpdate: { errors: ['boom'] } } });

      describe('with no saved content', () => {
        beforeEach(async () => {
          createComponent({ isPanelOpen: true, mutationHandler: failingHandler });
          await findPanel().vm.$emit('save', 'broken');
          await waitForPromises();
        });

        it('surfaces a mutation error via createAlert and Sentry', () => {
          expect(createAlert).toHaveBeenCalled();
        });
      });

      describe('and content was already saved', () => {
        const typedFailingHandler = jest.fn().mockResolvedValue({
          data: { workItemUpdate: { __typename: 'WorkItemUpdatePayload', errors: ['boom'] } },
        });

        beforeEach(async () => {
          createComponent({
            content: 'saved plan',
            isPanelOpen: true,
            mutationHandler: typedFailingHandler,
          });
          await waitForPromises();

          await findPanel().vm.$emit('save', 'unsaved edit');
          await waitForPromises();
        });

        it('does not write the attempted content to the cache', () => {
          expect(findPanel().props('savedContent')).toBe('saved plan');
          expect(findPanel().props('savedContentHtml')).toBe(paragraphHtml('saved plan'));
        });
      });
    });
  });

  describe('handleDelete', () => {
    describe('when confirmed', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(true);
        createComponent({ content: 'old plan', isPanelOpen: true });
        await findPanel().vm.$emit('delete');
        await waitForPromises();
      });

      it('clears the saved plan via the mutation', () => {
        expect(successMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({
            input: { id: mockWorkItemId, agentPlanWidget: { content: '' } },
          }),
        );
      });

      it('clears the draft', () => {
        expect(clearDraft).toHaveBeenCalledWith(planStorageKey);
      });
    });

    describe('when the confirm modal is dismissed', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(false);
        createComponent({ content: 'old plan', isPanelOpen: true });
        await findPanel().vm.$emit('delete');
        await waitForPromises();
      });

      it('aborts', () => {
        expect(successMutationHandler).not.toHaveBeenCalled();
      });
    });
  });

  describe('handleDraftChange', () => {
    describe('when the panel emits a value', () => {
      beforeEach(async () => {
        createComponent({ isPanelOpen: true });
        await findPanel().vm.$emit('draft-change', 'half-typed plan');
      });

      it('persists the draft to storage on every keystroke', () => {
        expect(updateDraft).toHaveBeenCalledWith(planStorageKey, 'half-typed plan');
      });
    });

    describe('when the panel emits an empty value', () => {
      beforeEach(async () => {
        createComponent({ isPanelOpen: true });
        await findPanel().vm.$emit('draft-change', '');
      });

      it('clears the draft', () => {
        expect(clearDraft).toHaveBeenCalledWith(planStorageKey);
      });
    });
  });

  describe('Generate MR with Duo wiring', () => {
    describe('when remote flows are disabled', () => {
      beforeEach(() => {
        createComponent({ duoRemoteFlowsAvailability: false, content: 'A plan' });
      });

      it('keeps the saved workplan available in the row and panel', () => {
        expect(findInlineRow().props('hasContent')).toBe(true);
        expect(findPanel().props('savedContent')).toBe('A plan');
      });
    });

    describe('when no plan exists', () => {
      beforeEach(() => {
        createComponent({ duoRemoteFlowsAvailability: true, content: '' });
      });

      it('passes hasContent=false', () => {
        expect(findInlineRow().props('hasContent')).toBe(false);
      });
    });

    describe('when remote flows are enabled', () => {
      beforeEach(() => {
        createComponent({ duoRemoteFlowsAvailability: true, content: 'A plan' });
      });

      it('forwards the work-item identifiers the MR button needs', () => {
        expect(findInlineRow().props()).toMatchObject({
          projectPath: 'group/project',
          workItemIid: '1',
          workItemType: 'Epic',
          workItemWebUrl: mockWorkItemWebUrl,
        });
      });

      it('forwards the work-item identifiers to the panel', () => {
        expect(findPanel().props()).toMatchObject({
          workItemIid: '1',
          workItemType: 'Epic',
          workItemWebUrl: mockWorkItemWebUrl,
        });
      });
    });
  });

  describe('async generation status', () => {
    it('forwards the status, reporting the refinement phase until the flow pauses', () => {
      createComponent({ workplan: buildWorkplan({ generationStatus: 'GENERATING' }) });

      expect(findInlineRow().props('generation')).toMatchObject({
        status: 'GENERATING',
        hasAwaitedInput: false,
      });
    });

    it('remembers that the flow paused, so a later run is the plan-writing pass', async () => {
      createComponent({ workplan: buildWorkplan({ generationStatus: 'GENERATING' }) });

      expect(findInlineRow().props('generation').hasAwaitedInput).toBe(false);

      await pushWorkplan({ generationStatus: 'NEEDS_INPUT' });
      await pushWorkplan({ generationStatus: 'GENERATING' });

      expect(findInlineRow().props('generation').hasAwaitedInput).toBe(true);
    });

    it('keeps the panel closed once a running flow lands its plan', async () => {
      createComponent({ workplan: buildWorkplan({ generationStatus: 'GENERATING' }) });

      expect(wrapper.emitted('request-panel')).toBeUndefined();

      await pushWorkplan({ content: 'the plan', generationStatus: 'COMPLETED' });

      expect(wrapper.emitted('request-panel')).toBeUndefined();
      expect(findInlineRow().props('hasContent')).toBe(true);
    });
  });

  describe('starting a run from the widget', () => {
    const failedPlan = buildWorkplan({ generationStatus: 'FAILED' });

    describe.each`
      trigger        | findSource
      ${'the row'}   | ${() => findInlineRow()}
      ${'the panel'} | ${() => findPanel()}
    `('when $trigger asks to generate', ({ findSource }) => {
      let generateHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        createComponent({ generateHandler });

        findSource().vm.$emit('generate');
        await waitForPromises();
      });

      it('starts a run for the work item', () => {
        expect(generateHandler).toHaveBeenCalledWith({ input: { id: mockWorkItemId } });
      });
    });

    describe('when retrying a run that failed', () => {
      let generateHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        createComponent({ workplan: failedPlan, generateHandler });

        findInlineRow().vm.$emit('retry');
        await waitForPromises();
      });

      it('starts a run for the work item', () => {
        expect(generateHandler).toHaveBeenCalledWith({ input: { id: mockWorkItemId } });
      });

      it('asks the parent to re-read the plan, since it owns the query', () => {
        expect(wrapper.emitted('refetch-plan')).toHaveLength(1);
      });
    });

    describe('when resuming a run that is waiting on the user', () => {
      const pausedPlan = buildWorkplan({ generationStatus: 'NEEDS_INPUT' });
      let resumeHandler;

      beforeEach(async () => {
        resumeHandler = resumeHandlerFor();
        createComponent({ workplan: pausedPlan, resumeHandler });

        findInlineRow().vm.$emit('continue');
        await waitForPromises();
      });

      it('resumes the run for the work item', () => {
        expect(resumeHandler).toHaveBeenCalledWith({ input: { id: mockWorkItemId } });
      });

      it('asks the parent to re-read the plan, since it owns the query', () => {
        expect(wrapper.emitted('refetch-plan')).toHaveLength(1);
      });

      it('alerts the service message verbatim when the resume is refused', async () => {
        createComponent({
          workplan: pausedPlan,
          resumeHandler: resumeHandlerFor({
            errors: ['Workplan generation is not awaiting input'],
          }),
        });

        findInlineRow().vm.$emit('continue');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Workplan generation is not awaiting input',
        });
      });

      it('alerts a generic message and captures the error when the mutation rejects', async () => {
        createComponent({
          workplan: pausedPlan,
          resumeHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });

        findInlineRow().vm.$emit('continue');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong while resuming workplan generation.',
          captureError: true,
          error: expect.any(Error),
        });
      });
    });

    describe('once the mutation has returned', () => {
      const pausedPlan = buildWorkplan({ generationStatus: 'NEEDS_INPUT' });

      const resume = async () => {
        findInlineRow().vm.$emit('continue');
        await waitForPromises();
      };
      const actionInFlight = () => findInlineRow().props('generation').actionInFlight;

      // The run keeps reporting NEEDS_INPUT for seconds after the resume is accepted,
      // so releasing the action on the mutation alone re-offers Continue in that gap.
      it('keeps the action pending while the run still reports its old status', async () => {
        createComponent({ workplan: pausedPlan });

        await resume();

        expect(actionInFlight()).toBe(true);
      });

      it('releases the action once the run reports a new status', async () => {
        createComponent({ workplan: pausedPlan });
        await resume();

        await pushWorkplan({ generationStatus: 'GENERATING' });

        expect(actionInFlight()).toBe(false);
      });

      it('releases the action when the run never reports a new status', async () => {
        createComponent({ workplan: pausedPlan });
        await resume();

        jest.advanceTimersByTime(FLOW_ACTION_TIMEOUT_MS);
        await nextTick();

        expect(actionInFlight()).toBe(false);
      });

      // Without this, a watchdog armed by an earlier action outlives it and releases
      // whichever action happens to be pending when it finally fires.
      it('drops the watchdog once the run reports a new status', async () => {
        createComponent({ workplan: pausedPlan });
        await resume();
        await pushWorkplan({ generationStatus: 'GENERATING' });

        findInlineRow().vm.$emit('continue');
        await waitForPromises();
        jest.advanceTimersByTime(FLOW_ACTION_TIMEOUT_MS - 1);
        await nextTick();

        expect(actionInFlight()).toBe(true);
      });

      it('drops the watchdog when the component is destroyed', async () => {
        const clearTimeoutSpy = jest.spyOn(global, 'clearTimeout');
        createComponent({ workplan: pausedPlan });
        await resume();
        // Only calls made while tearing down count, since arming clears too.
        clearTimeoutSpy.mockClear();

        wrapper.destroy();

        expect(clearTimeoutSpy).toHaveBeenCalled();
      });

      it('releases the action right away when the service refuses the resume', async () => {
        createComponent({
          workplan: pausedPlan,
          resumeHandler: resumeHandlerFor({ errors: ['Not awaiting input'] }),
        });

        await resume();

        expect(actionInFlight()).toBe(false);
      });

      it('releases the action right away when the mutation rejects', async () => {
        createComponent({
          workplan: pausedPlan,
          resumeHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });

        await resume();

        expect(actionInFlight()).toBe(false);
      });
    });

    it('marks the action as in flight while the mutation runs', async () => {
      createComponent({
        workplan: failedPlan,
        generateHandler: jest.fn().mockReturnValue(new Promise(() => {})),
      });

      expect(findInlineRow().props('generation').actionInFlight).toBe(false);

      findInlineRow().vm.$emit('retry');
      await nextTick();

      expect(findInlineRow().props('generation').actionInFlight).toBe(true);
    });

    describe('when the run cannot be started', () => {
      it('alerts the service message verbatim', async () => {
        createComponent({
          workplan: failedPlan,
          generateHandler: generateHandlerFor({
            errors: ['Async workplan generation is not enabled for this project'],
          }),
        });

        findInlineRow().vm.$emit('retry');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Async workplan generation is not enabled for this project',
        });
      });

      it('alerts a generic message and captures the error when the mutation rejects', async () => {
        createComponent({
          workplan: failedPlan,
          generateHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });

        findInlineRow().vm.$emit('retry');
        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong while starting workplan generation.',
          captureError: true,
          error: expect.any(Error),
        });
      });
    });
  });

  describe('opening workplan sessions', () => {
    let emitSpy;

    const triggerWorkplanAction = async (event, findSource = findInlineRow) => {
      findSource().vm.$emit(event);
      await waitForPromises();
    };

    const buildFailedGenerationHandler = ({ errors = [] } = {}) => {
      const response = buildWorkplanFlowMutationResponse('workItemGenerateWorkplan', { errors });
      response.data.workItemGenerateWorkplan.workflow = null;
      return jest.fn().mockResolvedValue(response);
    };

    beforeEach(() => {
      emitSpy = jest.spyOn(eventHub, '$emit');
    });

    afterEach(() => {
      emitSpy.mockRestore();
    });

    it.each([
      ['inline generate', 'generate', findInlineRow],
      ['panel generate', 'generate', findPanel],
      ['try again', 'retry', findInlineRow],
      ['regenerate', 'regenerate', findPanel],
    ])('opens the returned session after %s', async (name, event, findSource) => {
      createComponent();
      await triggerWorkplanAction(event, findSource);

      expect(emitSpy).toHaveBeenCalledWith(SHOW_SESSION, { id: 7 });
    });

    it('opens the session returned by each successive generation', async () => {
      const secondResponse = buildWorkplanFlowMutationResponse('workItemGenerateWorkplan');
      secondResponse.data.workItemGenerateWorkplan.workflow.id =
        'gid://gitlab/Ai::DuoWorkflows::Workflow/8';
      const generateHandler = generateHandlerFor().mockResolvedValueOnce(secondResponse);
      createComponent({ generateHandler });

      await triggerWorkplanAction('generate');
      expect(emitSpy).toHaveBeenCalledWith(SHOW_SESSION, { id: 8 });

      emitSpy.mockClear();
      await triggerWorkplanAction('generate');
      expect(emitSpy).toHaveBeenCalledWith(SHOW_SESSION, { id: 7 });
    });

    describe('when Continue is clicked on a freshly loaded paused workplan', () => {
      let resolveResume;
      let response;

      beforeEach(() => {
        response = buildWorkplanFlowMutationResponse('workItemResumeWorkplan');
        response.data.workItemResumeWorkplan.workflow.id =
          'gid://gitlab/Ai::DuoWorkflows::Workflow/42';
        createComponent({
          workplan: buildWorkplan({ generationStatus: 'NEEDS_INPUT' }),
          resumeHandler: jest.fn().mockReturnValue(
            new Promise((resolve) => {
              resolveResume = resolve;
            }),
          ),
        });
      });

      it('opens the returned session only after Continue succeeds', async () => {
        await triggerWorkplanAction('continue');

        expect(emitSpy).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());

        resolveResume(response);
        await waitForPromises();

        expect(emitSpy).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
      });
    });

    describe.each(['service error', 'network error', 'missing workflow'])(
      'when Continue returns a %s',
      (failure) => {
        beforeEach(() => {
          const response = buildWorkplanFlowMutationResponse('workItemResumeWorkplan', {
            errors: failure === 'service error' ? ['Cannot resume'] : [],
          });
          if (failure === 'missing workflow') {
            response.data.workItemResumeWorkplan.workflow = null;
          }
          const resumeHandler =
            failure === 'network error'
              ? jest.fn().mockRejectedValue(new Error('network error'))
              : jest.fn().mockResolvedValue(response);
          createComponent({
            workplan: buildWorkplan({ generationStatus: 'NEEDS_INPUT' }),
            resumeHandler,
          });
        });

        it('does not open a session', async () => {
          await triggerWorkplanAction('continue');

          expect(emitSpy).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());
        });
      },
    );

    it.each([
      ['service', () => buildFailedGenerationHandler({ errors: ['Cannot start'] })],
      ['network', () => jest.fn().mockRejectedValue(new Error('network error'))],
      ['missing workflow', () => buildFailedGenerationHandler()],
    ])('does not open a session after %s failure', async (failure, buildHandler) => {
      createComponent({ generateHandler: buildHandler() });
      await triggerWorkplanAction('retry');

      expect(emitSpy).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());
    });
  });

  describe('refetching the agent sessions list', () => {
    let emitSpy;

    beforeEach(() => {
      emitSpy = jest.spyOn(eventHub, '$emit');
    });

    afterEach(() => {
      emitSpy.mockRestore();
    });

    describe('when a run starts successfully', () => {
      beforeEach(async () => {
        createComponent({ generateHandler: generateHandlerFor() });

        findInlineRow().vm.$emit('generate');
        await waitForPromises();
      });

      it('signals that the sessions list is stale', () => {
        expect(emitSpy).toHaveBeenCalledWith(REFETCH_SESSIONS);
      });
    });

    describe('when the run cannot be started', () => {
      beforeEach(async () => {
        createComponent({
          generateHandler: generateHandlerFor({ errors: ['nope'] }),
        });

        findInlineRow().vm.$emit('generate');
        await waitForPromises();
      });

      it('does not signal that the sessions list is stale', () => {
        expect(emitSpy).not.toHaveBeenCalledWith(REFETCH_SESSIONS);
      });
    });
  });

  describe('when a first run lands its plan', () => {
    const generatingNoPlan = buildWorkplan({ content: '', generationStatus: 'GENERATING' });
    const landedPlan = { content: 'A fresh plan', generationStatus: 'GENERATING' };

    // The plan write is pushed immediately, the terminal status is not, so the run is
    // over well before the poll says so.
    it('reports the run as finished, without waiting for the status to catch up', async () => {
      createComponent({ workplan: generatingNoPlan });

      expect(findInlineRow().props('generation').status).toBe('GENERATING');

      await pushWorkplan(landedPlan);

      expect(findPanel().props('isFlowActive')).toBe(false);
    });

    it('defers to the status again once another run starts', async () => {
      createComponent({ workplan: generatingNoPlan });
      await pushWorkplan(landedPlan);

      expect(findPanel().props('isFlowActive')).toBe(false);

      findPanel().vm.$emit('regenerate');
      await waitForPromises();

      expect(findPanel().props('isFlowActive')).toBe(true);
    });
  });

  describe.each`
    generationStatus
    ${'GENERATING'}
    ${'NEEDS_INPUT'}
  `('when the page loads while a regenerate is $generationStatus', ({ generationStatus }) => {
    // The parent's query has not resolved on mount, so the saved plan arrives as a change.
    beforeEach(async () => {
      createComponent({ workplan: null });
      await pushWorkplan({ content: 'Old plan', generationStatus });
    });

    it('reports the run as active', () => {
      expect(findInlineRow().props('generation').isRunning).toBe(true);
      expect(findPanel().props('isFlowActive')).toBe(true);
      expect(wrapper.emitted('run-active').at(-1)).toEqual([true]);
    });

    it('reports the run as finished once the new plan lands', async () => {
      await pushWorkplan({ content: 'Fresh plan', generationStatus });

      expect(findInlineRow().props('generation').isRunning).toBe(false);
      expect(wrapper.emitted('run-active').at(-1)).toEqual([false]);
    });
  });

  describe('the panel across a regenerate', () => {
    const generating = buildWorkplan({ content: 'Old plan', generationStatus: 'GENERATING' });

    it('closes, rather than sitting empty for the length of the run', async () => {
      createComponent({
        content: 'Old plan',
        isPanelOpen: true,
      });

      findPanel().vm.$emit('regenerate');
      await waitForPromises();

      expect(wrapper.emitted('request-panel').at(-1)).toEqual([null]);
    });

    it('stays closed once the new plan lands', async () => {
      createComponent({
        workplan: generating,
        isPanelOpen: true,
      });
      findPanel().vm.$emit('regenerate');
      await waitForPromises();
      await wrapper.setProps({ isPanelOpen: false });

      await pushWorkplan({ content: 'Fresh plan', generationStatus: 'GENERATING' });

      expect(wrapper.emitted('request-panel')).toEqual([[null]]);
    });
  });

  describe('when a run momentarily reads as finished', () => {
    const generating = buildWorkplan({ content: 'Old plan', generationStatus: 'GENERATING' });
    const settled = { content: 'Old plan', generationStatus: 'COMPLETED' };
    const settledPlan = buildWorkplan(settled);

    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    // A stale read must not end the run, or it stops the polling that would correct it.
    it('keeps reporting the run as active', async () => {
      createComponent({ workplan: generating });
      findPanel().vm.$emit('regenerate');
      await waitForPromises();

      expect(wrapper.emitted('run-active').at(-1)).toEqual([true]);

      await pushWorkplan(settled);

      expect(wrapper.emitted('run-active').at(-1)).toEqual([true]);
    });

    it('stops expecting a run when the status never moves at all', async () => {
      createComponent({ workplan: settledPlan });
      findPanel().vm.$emit('regenerate');
      await waitForPromises();

      expect(wrapper.emitted('run-active').at(-1)).toEqual([true]);

      jest.advanceTimersByTime(TERMINAL_STATUS_CONFIRM_MS);
      await nextTick();

      expect(wrapper.emitted('run-active').at(-1)).toEqual([false]);
    });

    it('accepts the terminal status once a later read still agrees', async () => {
      createComponent({ workplan: generating });
      findPanel().vm.$emit('regenerate');
      await waitForPromises();
      await pushWorkplan(settled);

      jest.advanceTimersByTime(TERMINAL_STATUS_CONFIRM_MS);
      await nextTick();

      expect(wrapper.emitted('run-active').at(-1)).toEqual([false]);
    });

    it('ends the run as soon as the new plan lands, without waiting to confirm', async () => {
      createComponent({ workplan: generating });
      findPanel().vm.$emit('regenerate');
      await waitForPromises();

      await pushWorkplan({ content: 'Fresh plan', generationStatus: 'GENERATING' });

      expect(wrapper.emitted('run-active').at(-1)).toEqual([false]);
    });
  });

  describe('regenerating an existing workplan', () => {
    const savedPlanContent = 'An existing plan';
    let generateHandler;

    beforeEach(async () => {
      generateHandler = generateHandlerFor();
      createComponent({
        content: savedPlanContent,
        generateHandler,
      });

      findPanel().vm.$emit('regenerate');
      await waitForPromises();
    });

    it('starts a run for the work item', () => {
      expect(generateHandler).toHaveBeenCalledWith({ input: { id: mockWorkItemId } });
    });
  });
});
