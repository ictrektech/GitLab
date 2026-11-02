import { GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import WorkplanPanel from 'ee/work_items/components/implementation_widget/workplan_panel.vue';
import WorkplanView from 'ee/work_items/components/implementation_widget/workplan_view.vue';
import WorkplanEditor from 'ee/work_items/components/implementation_widget/workplan_editor.vue';
import WorkplanAvailabilityPopover from 'ee/work_items/components/implementation_widget/workplan_availability_popover.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import { isValidReadinessScore } from 'ee/work_items/components/implementation_widget/utils';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import {
  WORKPLAN_GOAL_PREFIX,
  WORKPLAN_SOURCE,
  GENERATE_MR_BUTTON_OPTIONS,
} from 'ee/work_items/components/implementation_widget/constants';

const MountingPortalStub = {
  name: 'MountingPortal',
  template: '<div data-testid="mounting-portal-stub"><slot /></div>',
};

const DynamicPanelStub = {
  name: 'DynamicPanel',
  props: ['shouldFillContent'],
  template: '<div><slot name="header"></slot><slot name="actions"></slot><slot></slot></div>',
};

const defaultProps = {
  generationDisabledReason: '',
  open: true,
  canUpdate: true,
  savedContent: '',
  savedContentHtml: '',
  draftContent: '',
  isEditing: false,
  isSaving: false,
  isLoading: false,
  workItemIid: '1',
  workItemType: 'Issue',
  workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
};

describe('WorkplanPanel', () => {
  let wrapper;
  const closeDropdown = jest.fn();

  const createComponent = ({ fullPath = 'group/project', ...props } = {}) => {
    wrapper = shallowMountExtended(WorkplanPanel, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: { fullPath },
      stubs: {
        MountingPortal: MountingPortalStub,
        DynamicPanel: DynamicPanelStub,
        GlDisclosureDropdown: stubComponent(GlDisclosureDropdown, {
          template: RENDER_ALL_SLOTS_TEMPLATE,
          methods: { close: closeDropdown },
        }),
      },
    });
  };

  const findPortal = () => wrapper.findByTestId('mounting-portal-stub');
  const findPanel = () => wrapper.findByTestId('workplan-panel');
  const findDynamicPanel = () => wrapper.findComponent(DynamicPanel);
  const findView = () => wrapper.findComponent(WorkplanView);
  const findEditor = () => wrapper.findComponent(WorkplanEditor);
  const findEditButton = () => wrapper.findComponentByTestId('panel-edit-button');
  const findMoreActionsDropdown = () => wrapper.findComponentByTestId('panel-edit-more-actions');
  const findRegenerateItem = () => wrapper.findComponentByTestId('regenerate-workplan-item');
  const findDeleteItem = () => wrapper.findComponentByTestId('delete-workplan-item');
  const findGenerateMrButton = () => wrapper.findByTestId('panel-generate-mr-with-duo');

  describe('rendering', () => {
    describe('when open is false', () => {
      beforeEach(() => {
        createComponent({ open: false });
      });

      it('does not render the portal', () => {
        expect(findPortal().exists()).toBe(false);
      });
    });

    describe('when open is true', () => {
      beforeEach(() => {
        createComponent({ open: true });
      });

      it('renders the panel chrome', () => {
        expect(findPanel().exists()).toBe(true);
      });
    });
  });

  describe('mode switching', () => {
    describe('when not editing', () => {
      beforeEach(() => {
        createComponent({ isEditing: false, savedContent: 'plan' });
      });

      it('renders the view and not the editor', () => {
        expect(findView().exists()).toBe(true);
        expect(findEditor().exists()).toBe(false);
      });

      it('does not fill the panel content', () => {
        expect(findDynamicPanel().props('shouldFillContent')).toBe(false);
      });

      it('forwards the view props', () => {
        expect(findView().props()).toMatchObject({
          isLoading: false,
          canUpdate: true,
          savedContent: 'plan',
        });
      });

      describe('when the view emits start-edit', () => {
        beforeEach(() => {
          findView().vm.$emit('start-edit');
        });

        it('emits "start-edit"', () => {
          expect(wrapper.emitted('start-edit')).toHaveLength(1);
        });
      });
    });

    describe('when editing', () => {
      beforeEach(() => {
        createComponent({ isEditing: true, savedContent: 'plan', draftContent: 'draft' });
      });

      it('renders the editor and not the view', () => {
        expect(findEditor().exists()).toBe(true);
        expect(findView().exists()).toBe(false);
      });

      it('fills the panel content so the editor stretches to the panel height', () => {
        expect(findDynamicPanel().props('shouldFillContent')).toBe(true);
      });

      it('forwards the editor props', () => {
        expect(findEditor().props()).toMatchObject({
          savedContent: 'plan',
          draftContent: 'draft',
          isSaving: false,
        });
      });

      describe('when the editor emits save', () => {
        beforeEach(() => {
          findEditor().vm.$emit('save', 'updated plan');
        });

        it('emits "save" with the content', () => {
          expect(wrapper.emitted('save')).toEqual([['updated plan']]);
        });
      });

      describe('when the editor emits cancel-edit', () => {
        beforeEach(() => {
          findEditor().vm.$emit('cancel-edit');
        });

        it('emits "cancel-edit"', () => {
          expect(wrapper.emitted('cancel-edit')).toHaveLength(1);
        });
      });

      describe('when the editor emits draft-change', () => {
        beforeEach(() => {
          findEditor().vm.$emit('draft-change', 'half-typed');
        });

        it('emits "draft-change" with the value', () => {
          expect(wrapper.emitted('draft-change')).toEqual([['half-typed']]);
        });
      });
    });
  });

  describe('Generate MR action', () => {
    describe('when content exists', () => {
      beforeEach(() => {
        createComponent({ savedContent: 'Some plan content' });
      });

      it('renders the button', () => {
        expect(findGenerateMrButton().exists()).toBe(true);
      });

      it('forwards the expected props to DuoWorkItemToMrAction', () => {
        expect(wrapper.findComponent(DuoWorkItemToMrAction).props()).toMatchObject({
          projectPath: 'group/project',
          workItemIid: '1',
          workItemType: 'Issue',
          workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
          additionalGoalContext: WORKPLAN_GOAL_PREFIX,
          source: WORKPLAN_SOURCE,
          generateMrButtonOptions: { ...GENERATE_MR_BUTTON_OPTIONS, size: 'small' },
        });
        expect(wrapper.findComponent(DuoWorkItemToMrAction).attributes()).toMatchObject({
          'disabled-flow-message':
            "Implementation with GitLab Duo isn't turned on for this project.",
          'disabled-flow-help-path':
            '/help/user/work_items/workplan#implement-a-workplan-with-gitlab-duo',
        });
      });

      it('overrides the button size to small to match the header buttons', () => {
        expect(
          wrapper.findComponent(DuoWorkItemToMrAction).props('generateMrButtonOptions').size,
        ).toBe('small');
      });
    });

    describe('tracking', () => {
      const { bindInternalEventDocument } = useMockInternalEventsTracking();

      it.each`
        readinessScore | expectedProperties
        ${75}          | ${{ property: 'panel', value: 75 }}
        ${0}           | ${{ property: 'panel', value: 0 }}
        ${null}        | ${{ property: 'panel' }}
      `(
        'tracks the Implement click when the readiness score is $readinessScore',
        ({ readinessScore, expectedProperties }) => {
          createComponent({ savedContent: 'Some plan content', readinessScore });
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

          wrapper.findComponent(DuoWorkItemToMrAction).vm.$emit('triggering');

          expect(trackEventSpy).toHaveBeenCalledTimes(1);
          expect(trackEventSpy).toHaveBeenCalledWith(
            'click_work_item_workplan_implement',
            expectedProperties,
          );
        },
      );
    });

    describe('when there is no saved content', () => {
      beforeEach(() => {
        createComponent({ savedContent: '' });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });
    });

    describe('when in edit mode', () => {
      beforeEach(() => {
        createComponent({
          savedContent: 'Some plan content',
          isEditing: true,
        });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });
    });

    describe('when the work item is closed', () => {
      beforeEach(() => {
        createComponent({ savedContent: 'Some plan content', isWorkItemClosed: true });
      });

      it('does not render the button', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });

      it('still renders the Edit button', () => {
        expect(findEditButton().exists()).toBe(true);
      });
    });
  });

  describe('more actions dropdown', () => {
    describe('when generation is unavailable', () => {
      beforeEach(() => {
        createComponent({
          savedContent: 'Some plan',
          generationDisabledReason: "Workplan generation isn't turned on for this project.",
        });
      });

      it('blocks Regenerate while keeping Delete and Edit available', () => {
        const regenerate = findRegenerateItem().props('item');
        expect(regenerate.extraAttrs['aria-disabled']).toBe(true);
        regenerate.action();
        expect(wrapper.emitted('regenerate')).toBeUndefined();
        expect(findDeleteItem().props('disabled')).toBe(false);
        findDeleteItem().props('item').action();
        expect(wrapper.emitted('delete')).toHaveLength(1);
        expect(findEditButton().exists()).toBe(true);
      });

      it('explains why next to Regenerate', () => {
        const popover = wrapper.findComponent(WorkplanAvailabilityPopover);

        expect(popover.props('reason')).toBe(
          "Workplan generation isn't turned on for this project.",
        );
        expect(popover.props('target')()).toBe(findRegenerateItem().element);
      });

      it('keeps the menu open so the explanation stays reachable', () => {
        expect(findMoreActionsDropdown().props('autoClose')).toBe(false);
      });
    });

    describe('with saved content', () => {
      beforeEach(() => {
        createComponent({ savedContent: 'Some plan', canUpdate: true });
      });

      it('exposes Delete workplan as an option', () => {
        expect(findDeleteItem().props('item').text).toBe('Delete workplan');
      });

      it('exposes Regenerate workplan as an option', () => {
        expect(findRegenerateItem().props('item').text).toBe('Regenerate workplan');
      });

      it('does not render the availability popover', () => {
        expect(wrapper.findComponent(WorkplanAvailabilityPopover).exists()).toBe(false);
      });

      describe('when the Regenerate item is activated', () => {
        beforeEach(() => {
          findRegenerateItem().props('item').action();
        });

        it('emits "regenerate"', () => {
          expect(wrapper.emitted('regenerate')).toHaveLength(1);
        });
      });

      describe('when the Delete item is activated', () => {
        beforeEach(() => {
          findDeleteItem().props('item').action();
        });

        it('emits "delete"', () => {
          expect(wrapper.emitted('delete')).toHaveLength(1);
        });

        it('closes the menu before the confirmation opens', () => {
          expect(closeDropdown).toHaveBeenCalled();
        });
      });
    });

    describe('without saved content', () => {
      beforeEach(() => {
        createComponent({ savedContent: '', canUpdate: true });
      });

      it('hides the dropdown so Regenerate is not exposed', () => {
        expect(findMoreActionsDropdown().exists()).toBe(false);
      });
    });

    describe('header actions while a run is replacing the plan', () => {
      beforeEach(() => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          isFlowActive: true,
        });
      });

      it('hides Edit, since the plan is about to be replaced', () => {
        expect(findEditButton().exists()).toBe(false);
      });

      it('hides Implement, so Duo cannot start from a plan on its way out', () => {
        expect(findGenerateMrButton().exists()).toBe(false);
      });

      it('keeps More actions, whose items are disabled rather than hidden', () => {
        expect(findMoreActionsDropdown().exists()).toBe(true);
      });
    });

    describe('plan action availability while a run is active', () => {
      it('disables Delete too, so a run cannot silently undo it', () => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          isFlowActive: true,
        });

        expect(findDeleteItem().props('disabled')).toBe(true);
      });

      // The status lags the click, so the run is not active yet when the mutation fires.
      it.each([
        ['Regenerate workplan', findRegenerateItem],
        ['Delete workplan', findDeleteItem],
      ])('disables %s while the mutation is still in flight', (_, findItem) => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          isFlowActive: false,
          isActionInFlight: true,
        });

        expect(findItem().props('disabled')).toBe(true);
      });

      it.each`
        isFlowActive | disabled | description
        ${true}      | ${true}  | ${'a run owns the workplan'}
        ${false}     | ${false} | ${'no run is in progress'}
      `('is disabled=$disabled when $description', ({ isFlowActive, disabled }) => {
        createComponent({
          savedContent: 'Some plan',
          canUpdate: true,
          isFlowActive,
        });

        expect(findRegenerateItem().props('disabled')).toBe(disabled);
      });
    });
  });

  describe('header buttons', () => {
    describe('when the user can update and is not editing', () => {
      beforeEach(() => {
        createComponent({ canUpdate: true });
      });

      it('shows the Edit button', () => {
        expect(findEditButton().exists()).toBe(true);
      });

      describe('when the Edit button is clicked', () => {
        beforeEach(() => {
          findEditButton().vm.$emit('click');
        });

        it('emits "start-edit"', () => {
          expect(wrapper.emitted('start-edit')).toHaveLength(1);
        });
      });

      describe('when the panel emits close', () => {
        beforeEach(async () => {
          await findDynamicPanel().vm.$emit('close');
        });

        it('emits "close"', () => {
          expect(wrapper.emitted('close')).toHaveLength(1);
        });
      });
    });

    describe('when the user cannot update', () => {
      beforeEach(() => {
        createComponent({ canUpdate: false });
      });

      it('hides the Edit button', () => {
        expect(findEditButton().exists()).toBe(false);
      });
    });

    describe('when editing', () => {
      beforeEach(() => {
        createComponent({ canUpdate: true, savedContent: 'plan', isEditing: true });
      });

      it('hides the Edit button', () => {
        expect(findEditButton().exists()).toBe(false);
      });
    });
  });

  it('validates readinessScore with isValidReadinessScore', () => {
    expect(WorkplanPanel.props.readinessScore.validator).toBe(isValidReadinessScore);
  });

  describe('keyboard handling', () => {
    let addEventListenerSpy;
    let keydownHandler;

    beforeEach(() => {
      addEventListenerSpy = jest
        .spyOn(document, 'addEventListener')
        .mockImplementation((event, handler) => {
          if (event === 'keydown') keydownHandler = handler;
        });
    });

    afterEach(() => {
      addEventListenerSpy.mockRestore();
    });

    describe('when Escape is pressed while open', () => {
      beforeEach(() => {
        createComponent({ open: true });
        keydownHandler({ key: 'Escape' });
      });

      it('emits "close"', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when Escape is pressed while closed', () => {
      beforeEach(() => {
        createComponent({ open: false });
        keydownHandler({ key: 'Escape' });
      });

      it('does nothing', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('when a modal is open in the document', () => {
      beforeEach(() => {
        createComponent({ open: true });
        document.body.classList.add('modal-open');
        keydownHandler({ key: 'Escape' });
      });

      afterEach(() => {
        document.body.classList.remove('modal-open');
      });

      it('does not emit close', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });
});
