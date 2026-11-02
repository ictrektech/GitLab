import { GlButtonGroup, GlDisclosureDropdown, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { assertProps } from 'helpers/assert_props';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import WorkplanInlineRow from 'ee/work_items/components/implementation_widget/workplan_inline_row.vue';
import ImplementationWidgetSegment from 'ee/vue_shared/components/work_items/implementation_widget_segment.vue';
import WorkplanQuestionNavigator from 'ee/work_items/components/implementation_widget/workplan_question_navigator.vue';
import WorkplanStatusBar from 'ee/work_items/components/implementation_widget/workplan_status_bar.vue';
import WorkplanAvailabilityPopover from 'ee/work_items/components/implementation_widget/workplan_availability_popover.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import { isValidReadinessScore } from 'ee/work_items/components/implementation_widget/utils';
import {
  GENERATION_STATUSES_ACTIVE,
  WORKPLAN_SOURCE,
} from 'ee/work_items/components/implementation_widget/constants';

describe('WorkplanInlineRow', () => {
  let wrapper;

  const duoMrActionProps = {
    projectPath: 'group/project',
    workItemIid: '42',
    workItemType: 'Epic',
    workItemWebUrl: '/group/project/-/work_items/42',
    generateMrButtonOptions: { size: 'medium', variant: 'confirm', category: 'primary' },
  };

  const duoMrActionComponentProps = {
    hasContent: true,
    canUpdate: true,
    ...duoMrActionProps,
  };

  const defaultProps = {
    workItemIid: '42',
    isLoading: false,
  };

  // Takes the run state flat and assembles the `generation` prop, so each test reads as
  // the scenario it describes rather than as an object literal.
  const createComponent = (
    {
      generationStatus = null,
      hasAwaitedInput = false,
      isFlowActionInFlight = false,
      isRunning = GENERATION_STATUSES_ACTIVE.includes(generationStatus),
      isStarting = isRunning && !GENERATION_STATUSES_ACTIVE.includes(generationStatus),
      openQuestionsCount = null,
      hasQuestions = false,
      questions = [],
      ...props
    } = {},
    provide = {},
  ) => {
    wrapper = shallowMountExtended(WorkplanInlineRow, {
      propsData: {
        ...defaultProps,
        generation: {
          status: generationStatus,
          hasAwaitedInput,
          actionInFlight: isFlowActionInFlight,
          isRunning,
          isStarting,
          openQuestionsCount,
          hasQuestions,
          questions,
        },
        ...props,
      },
      provide: { glFeatures: {}, ...provide },
      stubs: { DuoWorkItemToMrAction: true, ImplementationWidgetSegment, HelpPopover, GlSprintf },
    });
  };

  const findRow = () => wrapper.findByTestId('workplan-inline-row');
  const findOpenButton = () => wrapper.findComponentByTestId('open-workplan-button');
  const findDuoWorkItemToMrAction = () => wrapper.findComponent(DuoWorkItemToMrAction);
  const findButtonGroup = () => wrapper.findComponent(GlButtonGroup);
  const findDisclosureDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findGenerateButton = () => wrapper.findComponentByTestId('inline-generate-button');
  const findHelpPopover = () => wrapper.findComponent(HelpPopover);
  const findHelpPopoverLink = () => findHelpPopover().findComponent(GlLink);
  const findWorkplanStatusBar = () => wrapper.findComponent(WorkplanStatusBar);
  const findQuestionNavigator = () => wrapper.findComponent(WorkplanQuestionNavigator);
  const findAwaitingInputIcon = () => wrapper.findComponentByTestId('awaiting-input-icon');
  const findRetryButton = () => wrapper.findComponentByTestId('retry-workplan-button');
  const findContinueButton = () => wrapper.findComponentByTestId('continue-workplan-button');

  describe('help popover', () => {
    it('is shown before a workplan exists', () => {
      createComponent({ hasContent: false });
      expect(findHelpPopover().exists()).toBe(true);
    });

    it('is hidden once a workplan exists', () => {
      createComponent({ hasContent: true });
      expect(findHelpPopover().exists()).toBe(false);
    });

    it('explains what a workplan is and links to the docs', () => {
      createComponent({ hasContent: false });
      expect(findHelpPopover().props('options').title).toBe('What is a workplan?');
      expect(findHelpPopover().text()).toContain('breaks a work item into clear, ordered steps');
      expect(findHelpPopoverLink().text()).toBe('Learn more');
      expect(findHelpPopoverLink().attributes('href')).toBe('/help/user/work_items/workplan');
    });
  });

  describe.each([
    ['Generate', 'NOT_STARTED', 'inline-generate-button'],
    ['Try again', 'FAILED', 'retry-workplan-button'],
    ['Continue', 'NEEDS_INPUT', 'continue-workplan-button'],
  ])('Duo action icon on %s', (label, generationStatus, testId) => {
    it('shows the Duo icon', () => {
      createComponent({ canUpdate: true, generationStatus });

      expect(wrapper.findComponentByTestId(testId).props('icon')).toBe('tanuki-ai');
    });

    it('keeps the Duo icon when the action is unavailable', () => {
      createComponent({
        canUpdate: true,
        generationStatus,
        generationDisabledReason: 'Unavailable.',
      });

      expect(wrapper.findComponentByTestId(testId).props('icon')).toBe('tanuki-ai');
    });
  });

  describe('actions that do not start a Duo flow', () => {
    it('does not put the Duo icon on View', () => {
      createComponent({ hasContent: true, canUpdate: true });

      expect(findOpenButton().props('icon')).toBe('');
    });

    it('does not put the Duo icon on the Create manually dropdown item', () => {
      createComponent({ hasContent: false, canUpdate: true });

      expect(findDisclosureDropdown().props('items')).toEqual([
        expect.not.objectContaining({ icon: expect.anything() }),
      ]);
    });
  });

  describe.each([
    ['Generate', 'NOT_STARTED', 'inline-generate-button'],
    ['Try again', 'FAILED', 'retry-workplan-button'],
    ['Continue', 'NEEDS_INPUT', 'continue-workplan-button'],
  ])('when %s is unavailable', (label, generationStatus, testId) => {
    const reason = "Workplan generation isn't turned on for this project.";

    beforeEach(() => {
      createComponent({ canUpdate: true, generationStatus, generationDisabledReason: reason });
    });

    it('keeps the action visible and accessibly disabled', () => {
      expect(wrapper.findComponentByTestId(testId).props()).toMatchObject({
        disabled: true,
        accessibleDisabled: true,
      });
    });

    it('explains why in the popover', () => {
      expect(wrapper.findComponent(WorkplanAvailabilityPopover).props('reason')).toBe(reason);
    });
  });

  describe.each([
    ['Generate', 'NOT_STARTED', 'inline-generate-button'],
    ['Try again', 'FAILED', 'retry-workplan-button'],
    ['Continue', 'NEEDS_INPUT', 'continue-workplan-button'],
  ])('when %s is available', (label, generationStatus, testId) => {
    beforeEach(() => {
      createComponent({ canUpdate: true, generationStatus });
    });

    it('enables the action', () => {
      expect(wrapper.findComponentByTestId(testId).props('disabled')).toBe(false);
    });

    it('does not render the popover', () => {
      expect(wrapper.findComponent(WorkplanAvailabilityPopover).exists()).toBe(false);
    });
  });

  describe.each([
    ['View', { hasContent: true, canUpdate: true }],
    ['no action', { canUpdate: false }],
  ])('when generation is unavailable and the action is %s', (label, props) => {
    it('does not render the popover', () => {
      createComponent({ ...props, generationDisabledReason: 'Unavailable.' });

      expect(wrapper.findComponent(WorkplanAvailabilityPopover).exists()).toBe(false);
    });
  });

  describe('status label', () => {
    describe('when there is no content', () => {
      describe('and user can update', () => {
        beforeEach(() => {
          createComponent({ hasContent: false, canUpdate: true });
        });

        it('shows "Not yet created"', () => {
          expect(findRow().text()).toContain('Workplan');
          expect(findRow().text()).toContain('Not yet created');
        });
      });

      describe('and user cannot update', () => {
        beforeEach(() => {
          createComponent({ hasContent: false, canUpdate: false });
        });

        it('shows "No workplan"', () => {
          expect(findRow().text()).toContain('No workplan');
        });
      });
    });

    describe('when there is content', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: true });
      });

      it('shows "Ready for review"', () => {
        expect(findRow().text()).toContain('Ready for review');
      });
    });
  });

  describe('create actions (empty state)', () => {
    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({ hasContent: false, canUpdate: false });
      });

      it('does not show a create action', () => {
        expect(findOpenButton().exists()).toBe(false);
        expect(findButtonGroup().exists()).toBe(false);
      });
    });

    describe('while the plan is still loading', () => {
      beforeEach(() => {
        createComponent({ hasContent: false, canUpdate: true, isLoading: true });
      });

      it('does not offer the create action until the fetch settles', () => {
        expect(findDisclosureDropdown().exists()).toBe(false);
      });
    });
  });

  describe('Split button with dropdown', () => {
    describe('when there is no content and user can update', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
          canUpdate: true,
        });
      });

      it('shows the button group', () => {
        expect(findButtonGroup().exists()).toBe(true);
      });

      it('shows the disclosure dropdown', () => {
        expect(findDisclosureDropdown().exists()).toBe(true);
      });

      it('dropdown contains "Create manually" option', () => {
        const dropdownItems = findDisclosureDropdown().props('items');
        expect(dropdownItems).toHaveLength(1);
        expect(dropdownItems[0].text).toBe('Create manually');
      });

      it('emits "create-manually" when dropdown action is triggered', async () => {
        await findDisclosureDropdown().vm.$emit('action');
        expect(wrapper.emitted('create-manually')).toHaveLength(1);
        expect(wrapper.emitted('open')).toBeUndefined();
      });
    });

    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({
          hasContent: true,
          canUpdate: true,
        });
      });

      it('does not show the split button', () => {
        expect(findButtonGroup().exists()).toBe(false);
      });
    });
  });

  describe('View toggle button', () => {
    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: true });
      });

      it('shows "View" button', () => {
        expect(findOpenButton().text()).toBe('View');
      });

      it('emits "open" when clicked', async () => {
        await findOpenButton().vm.$emit('click');
        expect(wrapper.emitted('open')).toHaveLength(1);
      });
    });

    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, canUpdate: false });
      });

      it('still shows the button (read-only viewers can view)', () => {
        expect(findOpenButton().exists()).toBe(true);
      });
    });

    describe('when panel is open', () => {
      beforeEach(() => {
        createComponent({ hasContent: true, isPanelOpen: true });
      });

      it('reflects the panel-open state via aria-pressed', () => {
        expect(findOpenButton().attributes('aria-pressed')).toBe('true');
      });
    });
  });

  describe('Duo actions', () => {
    describe('when content is missing', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
          canUpdate: true,
        });
      });

      it('shows Generate-workplan action', () => {
        expect(findGenerateButton().exists()).toBe(true);
      });

      it('does not show Generate-MR action', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    describe('when content exists', () => {
      describe('and the user can update', () => {
        beforeEach(() => {
          createComponent({
            ...duoMrActionComponentProps,
            canUpdate: true,
          });
        });

        it('does not show Generate-workplan action', () => {
          expect(findGenerateButton().exists()).toBe(false);
        });

        it('shows Generate-MR action', () => {
          expect(findDuoWorkItemToMrAction().exists()).toBe(true);
        });

        it('passes correct props to Generate-MR action', () => {
          expect(findDuoWorkItemToMrAction().props()).toMatchObject({
            ...duoMrActionProps,
            source: WORKPLAN_SOURCE,
          });
        });
      });
    });
  });

  describe('Duo "Generate MR" button', () => {
    describe('when content exists and the user can update', () => {
      beforeEach(() => {
        createComponent(duoMrActionComponentProps);
      });

      it('is shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(true);
      });

      it('passes correct props', () => {
        expect(findDuoWorkItemToMrAction().props()).toMatchObject({
          ...duoMrActionProps,
          source: WORKPLAN_SOURCE,
        });
      });
    });

    describe('when content is empty', () => {
      beforeEach(() => {
        createComponent({
          hasContent: false,
        });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    describe('when user cannot update', () => {
      beforeEach(() => {
        createComponent({
          hasContent: true,
          canUpdate: false,
        });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    describe('when the work item is closed', () => {
      beforeEach(() => {
        createComponent({ ...duoMrActionComponentProps, isWorkItemClosed: true });
      });

      it('is not shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });

      it('still shows the View button', () => {
        expect(findOpenButton().exists()).toBe(true);
      });
    });

    describe('when the work item is open', () => {
      beforeEach(() => {
        createComponent({ ...duoMrActionComponentProps, isWorkItemClosed: false });
      });

      it('is shown', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(true);
      });
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it.each`
        readinessScore | expectedProperties
        ${75}          | ${{ property: 'inline_row', value: 75 }}
        ${0}           | ${{ property: 'inline_row', value: 0 }}
        ${null}        | ${{ property: 'inline_row' }}
      `(
        'tracks the Implement click when the readiness score is $readinessScore',
        ({ readinessScore, expectedProperties }) => {
          createComponent({ ...duoMrActionComponentProps, readinessScore });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          findDuoWorkItemToMrAction().vm.$emit('triggering');

          expect(trackEventSpy).toHaveBeenCalledTimes(1);
          expect(trackEventSpy).toHaveBeenCalledWith(
            'click_work_item_workplan_implement',
            expectedProperties,
          );
        },
      );
    });

    it('passes correct props', () => {
      createComponent({
        hasContent: true,
        canUpdate: true,
        projectPath: 'group/project',
        workItemIid: '42',
        workItemType: 'Epic',
        workItemWebUrl: '/group/project/-/work_items/42',
      });
      expect(findDuoWorkItemToMrAction().props()).toMatchObject({
        projectPath: 'group/project',
        workItemIid: '42',
        workItemType: 'Epic',
        workItemWebUrl: '/group/project/-/work_items/42',
      });
      expect(findDuoWorkItemToMrAction().attributes()).toMatchObject({
        'disabled-flow-message': "Implementation with GitLab Duo isn't turned on for this project.",
        'disabled-flow-help-path':
          '/help/user/work_items/workplan#implement-a-workplan-with-gitlab-duo',
      });
    });
  });

  describe('signal bar', () => {
    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({ hasContent: true });
      });

      it('uses the success variant', () => {
        expect(findWorkplanStatusBar().props('variant')).toBe('success');
      });

      it('labels the bar with the status', () => {
        expect(findWorkplanStatusBar().attributes('aria-label')).toBe('Ready for review');
      });
    });

    describe('when content is missing', () => {
      beforeEach(() => {
        createComponent({ hasContent: false });
      });

      it('uses the neutral variant', () => {
        expect(findWorkplanStatusBar().props('variant')).toBe('neutral');
      });
    });
  });

  describe('async generation states', () => {
    describe.each`
      scenario                              | generationStatus | hasAwaitedInput | hasContent | label                       | variant
      ${'a run is reviewing the work item'} | ${'GENERATING'}  | ${false}        | ${false}   | ${'Reviewing work item...'} | ${'info'}
      ${'a resumed run is writing a plan'}  | ${'GENERATING'}  | ${true}         | ${false}   | ${'Generating workplan...'} | ${'info'}
      ${'a run is waiting on the user'}     | ${'NEEDS_INPUT'} | ${false}        | ${false}   | ${'Awaiting input'}         | ${'warning'}
      ${'a run ended without a plan'}       | ${'FAILED'}      | ${false}        | ${false}   | ${'Generation failed'}      | ${'error'}
      ${'a user canceled the run'}          | ${'CANCELED'}    | ${false}        | ${false}   | ${'Generation canceled'}    | ${'error'}
      ${'a run is writing over a plan'}     | ${'GENERATING'}  | ${false}        | ${true}    | ${'Generating workplan...'} | ${'info'}
      ${'a resumed run has a saved plan'}   | ${'GENERATING'}  | ${true}         | ${true}    | ${'Generating workplan...'} | ${'info'}
      ${'a run with a plan wants input'}    | ${'NEEDS_INPUT'} | ${false}        | ${true}    | ${'Awaiting input'}         | ${'warning'}
      ${'a plan outlives a failed run'}     | ${'FAILED'}      | ${false}        | ${true}    | ${'Ready for review'}       | ${'success'}
      ${'a plan outlives a canceled run'}   | ${'CANCELED'}    | ${false}        | ${true}    | ${'Ready for review'}       | ${'success'}
    `('when $scenario', ({ generationStatus, hasAwaitedInput, hasContent, label, variant }) => {
      beforeEach(() => {
        createComponent({ generationStatus, hasAwaitedInput, hasContent, canUpdate: true });
      });

      it(`reports "${label}"`, () => {
        expect(findRow().text()).toContain(label);
      });

      it(`marks the status bar ${variant}`, () => {
        expect(findWorkplanStatusBar().props('variant')).toBe(variant);
      });
    });

    describe.each`
      scenario                              | generationStatus | hasContent | generate | retry    | continueRun
      ${'a run is reviewing the work item'} | ${'GENERATING'}  | ${false}   | ${false} | ${false} | ${false}
      ${'a run is waiting on the user'}     | ${'NEEDS_INPUT'} | ${false}   | ${false} | ${false} | ${true}
      ${'a regenerate wants input'}         | ${'NEEDS_INPUT'} | ${true}    | ${false} | ${false} | ${true}
      ${'a run ended without a plan'}       | ${'FAILED'}      | ${false}   | ${false} | ${true}  | ${false}
      ${'a plan outlives a failed run'}     | ${'FAILED'}      | ${true}    | ${false} | ${false} | ${false}
      ${'a user canceled the run'}          | ${'CANCELED'}    | ${false}   | ${true}  | ${false} | ${false}
      ${'a plan outlives a canceled run'}   | ${'CANCELED'}    | ${true}    | ${false} | ${false} | ${false}
      ${'no run is in progress'}            | ${'COMPLETED'}   | ${false}   | ${true}  | ${false} | ${false}
    `('when $scenario', ({ generationStatus, hasContent, generate, retry, continueRun }) => {
      beforeEach(() => {
        createComponent({ generationStatus, hasContent, canUpdate: true });
      });

      it(`${generate ? 'offers' : 'withholds'} the Generate action`, () => {
        expect(findButtonGroup().exists()).toBe(generate);
      });

      it(`${retry ? 'offers' : 'withholds'} Try again`, () => {
        expect(findRetryButton().exists()).toBe(retry);
      });

      it(`${continueRun ? 'offers' : 'withholds'} Continue`, () => {
        expect(findContinueButton().exists()).toBe(continueRun);
      });
    });

    describe('when a run is waiting on the user and no plan exists yet', () => {
      beforeEach(() => {
        createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: false, canUpdate: true });
      });

      it('marks the status with the awaiting-input icon', () => {
        expect(findAwaitingInputIcon().props()).toMatchObject({
          name: 'status',
          variant: 'warning',
        });
      });

      it('hides the help popover, leaving the status as the only claim about the plan', () => {
        expect(findHelpPopover().exists()).toBe(false);
      });
    });

    describe('open questions count', () => {
      it.each`
        scenario                               | generationStatus | openQuestionsCount | hasQuestions | label
        ${'several questions are open'}        | ${'NEEDS_INPUT'} | ${2}               | ${true}      | ${'Awaiting input (2 questions)'}
        ${'one question is open'}              | ${'NEEDS_INPUT'} | ${1}               | ${true}      | ${'Awaiting input (1 question)'}
        ${'every question is answered'}        | ${'NEEDS_INPUT'} | ${0}               | ${true}      | ${'All questions resolved'}
        ${'the run paused without asking'}     | ${'NEEDS_INPUT'} | ${0}               | ${false}     | ${'Awaiting input'}
        ${'the count does not apply'}          | ${'NEEDS_INPUT'} | ${null}            | ${false}     | ${'Awaiting input'}
        ${'the run is no longer paused'}       | ${'GENERATING'}  | ${2}               | ${true}      | ${'Reviewing work item...'}
        ${'the run resumed with nothing left'} | ${'GENERATING'}  | ${0}               | ${true}      | ${'Reviewing work item...'}
      `(
        'reports "$label" when $scenario',
        ({ generationStatus, openQuestionsCount, hasQuestions, label }) => {
          createComponent({ generationStatus, openQuestionsCount, hasQuestions, canUpdate: true });

          expect(findWorkplanStatusBar().attributes('aria-label')).toBe(label);
          expect(findRow().text()).toContain(label);
        },
      );

      it('keeps the awaiting-input icon once every question is answered', () => {
        createComponent({
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 0,
          hasQuestions: true,
          canUpdate: true,
        });

        expect(findAwaitingInputIcon().exists()).toBe(true);
        expect(findWorkplanStatusBar().props('variant')).toBe('warning');
      });

      it('still offers Continue, since a run can resume with questions unanswered', () => {
        createComponent({
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 2,
          canUpdate: true,
        });

        expect(findContinueButton().exists()).toBe(true);
      });
    });

    describe('open questions navigation', () => {
      const questions = [{ noteId: 'gid://gitlab/DiscussionNote/1', answered: false }];

      describe('when the run is awaiting input with open questions', () => {
        beforeEach(() => {
          createComponent({ generationStatus: 'NEEDS_INPUT', openQuestionsCount: 1, questions });
        });

        it('renders the navigator with the questions', () => {
          expect(findQuestionNavigator().props('questions')).toEqual(questions);
        });
      });

      it.each`
        scenario                         | generationStatus | openQuestionsCount
        ${'every question is answered'}  | ${'NEEDS_INPUT'} | ${0}
        ${'the count does not apply'}    | ${'NEEDS_INPUT'} | ${null}
        ${'the run is no longer paused'} | ${'GENERATING'}  | ${1}
      `('hides the navigator when $scenario', ({ generationStatus, openQuestionsCount }) => {
        createComponent({ generationStatus, openQuestionsCount, questions });

        expect(findQuestionNavigator().exists()).toBe(false);
      });
    });

    it('keeps the awaiting-input icon when a regenerate wants input over a saved plan', () => {
      createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: true, canUpdate: true });

      expect(findAwaitingInputIcon().exists()).toBe(true);
    });

    it('offers Continue over View, so a paused regenerate can be answered', () => {
      createComponent({ generationStatus: 'NEEDS_INPUT', hasContent: true, canUpdate: true });

      expect(findContinueButton().exists()).toBe(true);
      expect(findOpenButton().exists()).toBe(false);
    });

    it('reads as ready the moment a first run lands its plan, before the status catches up', () => {
      createComponent({
        generationStatus: 'GENERATING',
        hasContent: true,
        isRunning: false,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Ready for review');
      expect(findWorkplanStatusBar().props('variant')).toBe('success');
    });

    it('reports the run before its status arrives, so a click is acknowledged at once', () => {
      createComponent({
        generationStatus: 'COMPLETED',
        hasContent: true,
        isRunning: true,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Preparing to generate...');
      expect(findWorkplanStatusBar().props('variant')).toBe('info');
    });

    it('drops the preparing status once the run reports itself', () => {
      createComponent({
        generationStatus: 'GENERATING',
        hasContent: true,
        canUpdate: true,
      });

      expect(findRow().text()).toContain('Generating workplan...');
    });

    describe('while a run is regenerating the plan', () => {
      beforeEach(() => {
        createComponent({
          generationStatus: 'GENERATING',
          hasContent: true,
          canUpdate: true,
        });
      });

      it('hides View, since the plan is about to be replaced', () => {
        expect(findOpenButton().exists()).toBe(false);
      });

      it('hides Implement, so Duo cannot start from a plan on its way out', () => {
        expect(findDuoWorkItemToMrAction().exists()).toBe(false);
      });
    });

    it('drops the awaiting-input icon when no run is waiting', () => {
      createComponent({ generationStatus: 'GENERATING', hasContent: false, canUpdate: true });

      expect(findAwaitingInputIcon().exists()).toBe(false);
    });

    describe('when a run is waiting on the user', () => {
      it('asks the parent to resume the run', () => {
        createComponent({ generationStatus: 'NEEDS_INPUT', canUpdate: true });

        findContinueButton().vm.$emit('click');

        expect(wrapper.emitted('continue')).toHaveLength(1);
      });

      it('withholds Continue from a user who cannot update the work item', () => {
        createComponent({ generationStatus: 'NEEDS_INPUT', canUpdate: false });

        expect(findContinueButton().exists()).toBe(false);
      });

      it('marks Continue as loading while the resume is in flight', () => {
        createComponent({
          generationStatus: 'NEEDS_INPUT',
          canUpdate: true,
          isFlowActionInFlight: true,
        });

        expect(findContinueButton().props('loading')).toBe(true);
      });
    });

    describe('when a run ended without a plan', () => {
      it('asks the parent to retry', () => {
        createComponent({ generationStatus: 'FAILED', canUpdate: true });

        findRetryButton().vm.$emit('click');

        expect(wrapper.emitted('retry')).toHaveLength(1);
      });

      it('withholds Try again from a user who cannot update the work item', () => {
        createComponent({ generationStatus: 'FAILED', canUpdate: false });

        expect(findRetryButton().exists()).toBe(false);
      });
    });
  });

  describe('when no workplan exists', () => {
    beforeEach(() => {
      createComponent({ hasContent: false, canUpdate: true });
    });

    it('offers Generate', () => {
      expect(findGenerateButton().exists()).toBe(true);
    });

    it('asks the parent to start a run', () => {
      findGenerateButton().vm.$emit('click');

      expect(wrapper.emitted('generate')).toHaveLength(1);
    });

    it('keeps the Create manually option alongside it', () => {
      expect(findDisclosureDropdown().exists()).toBe(true);
    });

    it('shows Generate as loading while a run is starting', () => {
      createComponent({
        hasContent: false,
        canUpdate: true,
        isFlowActionInFlight: true,
      });

      expect(findGenerateButton().props('loading')).toBe(true);
    });
  });

  it('validates readinessScore with isValidReadinessScore', () => {
    expect(WorkplanInlineRow.props.readinessScore.validator).toBe(isValidReadinessScore);
  });

  describe('generation prop validation', () => {
    it.each(['NOT_STARTED', 'GENERATING', 'NEEDS_INPUT', 'COMPLETED', 'CANCELED', 'FAILED', null])(
      'accepts the %s status',
      (status) => {
        expect(() =>
          assertProps(WorkplanInlineRow, { ...defaultProps, generation: { status } }),
        ).not.toThrow();
      },
    );

    it('rejects a status the backend enum cannot return', () => {
      expect(() =>
        assertProps(WorkplanInlineRow, { ...defaultProps, generation: { status: 'PENDING' } }),
      ).toThrow();
    });
  });
});
