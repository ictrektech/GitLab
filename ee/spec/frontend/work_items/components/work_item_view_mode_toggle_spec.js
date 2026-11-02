import { GlButtonGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import { makeMockUserCalloutDismisser } from 'helpers/mock_user_callout_dismisser';
import { VIEW_MODE_LIST, VIEW_MODE_BOARD, VIEW_MODE_TABLE } from '~/work_items/constants';
import WorkItemViewModeToggle from '~/work_items/components/work_item_view_mode_toggle.vue';
import WorkItemBoardViewPopover from '~/work_items/components/work_item_board_view_popover.vue';

// Pin this to the EE view modes regardless of which alias environment the suite runs under
// — the CE/EE difference itself is covered by view_modes_spec.js.
jest.mock('ee_else_ce/work_items/view_modes', () => jest.requireActual('ee/work_items/view_modes'));

describe('WorkItemViewModeToggle (EE)', () => {
  let wrapper;

  const findToggles = () => wrapper.findAllComponents(GlButtonGroup);
  const findIconButton = (viewMode) => wrapper.findComponentByTestId(`view-mode-icon-${viewMode}`);
  const findLabelButton = (viewMode) =>
    wrapper.findComponentByTestId(`view-mode-label-${viewMode}`);

  const createComponent = ({ props = {}, provide = {}, dismisserProps = {} } = {}) => {
    wrapper = shallowMountExtended(WorkItemViewModeToggle, {
      propsData: {
        viewMode: VIEW_MODE_LIST,
        isBoardEnabled: true,
        ...props,
      },
      provide: {
        glFeatures: {},
        ...provide,
      },
      stubs: {
        UserCalloutDismisser: makeMockUserCalloutDismisser(dismisserProps),
      },
    });
  };

  it('renders the list and board icons when the board is enabled', () => {
    createComponent();

    expect(findToggles()).toHaveLength(2);
    expect(findIconButton(VIEW_MODE_LIST).exists()).toBe(true);
    expect(findIconButton(VIEW_MODE_BOARD).exists()).toBe(true);
    expect(findIconButton(VIEW_MODE_TABLE).exists()).toBe(false);
  });

  it('renders a board icon button labelled for assistive tech', () => {
    createComponent();

    expect(findIconButton(VIEW_MODE_BOARD).props('icon')).toBe('columns');
    expect(findIconButton(VIEW_MODE_BOARD).attributes('aria-label')).toBe('Board');
    expect(findIconButton(VIEW_MODE_BOARD).attributes('title')).toBe('Board');
  });

  it('renders a board label button with text and no icon', () => {
    createComponent();

    expect(findLabelButton(VIEW_MODE_BOARD).text()).toBe('Board');
    expect(findLabelButton(VIEW_MODE_BOARD).props('icon')).toBe('');
  });

  it('emits toggle-view-mode with the clicked value from either variant', () => {
    createComponent();

    findIconButton(VIEW_MODE_BOARD).vm.$emit('click');
    findLabelButton(VIEW_MODE_BOARD).vm.$emit('click');

    expect(wrapper.emitted('toggle-view-mode')).toEqual([[VIEW_MODE_BOARD], [VIEW_MODE_BOARD]]);
  });

  it('omits the board button when the board is not enabled', () => {
    createComponent({ props: { isBoardEnabled: false } });

    expect(findToggles()).toHaveLength(0);
  });

  describe('when planningViewTable is also enabled', () => {
    beforeEach(() => {
      createComponent({ provide: { glFeatures: { planningViewTable: true } } });
    });

    it('renders list, board and table buttons', () => {
      expect(findIconButton(VIEW_MODE_LIST).exists()).toBe(true);
      expect(findIconButton(VIEW_MODE_BOARD).exists()).toBe(true);
      expect(findIconButton(VIEW_MODE_TABLE).exists()).toBe(true);
    });

    it('omits the board button when the board is not enabled', () => {
      createComponent({
        props: { isBoardEnabled: false },
        provide: { glFeatures: { planningViewTable: true } },
      });

      expect(findToggles()).toHaveLength(2);
      expect(findIconButton(VIEW_MODE_BOARD).exists()).toBe(false);
      expect(findIconButton(VIEW_MODE_TABLE).exists()).toBe(true);
    });
  });

  describe('board view popover', () => {
    useFakeDate(2026, 10, 19);

    const findHotspot = () => wrapper.findByTestId('board-view-hotspot');
    const findPopovers = () => wrapper.findAllComponents(WorkItemBoardViewPopover);

    it('is hidden by default', () => {
      createComponent();

      expect(findHotspot().exists()).toBe(false);
      expect(findPopovers()).toHaveLength(0);
    });

    it('renders the hotspot and a popover for each board button', () => {
      createComponent({ props: { showBoardPopover: true } });

      expect(findHotspot().exists()).toBe(true);
      expect(findPopovers()).toHaveLength(2);
      expect(findPopovers().at(0).props('target')()).toBe(findIconButton(VIEW_MODE_BOARD).element);
      expect(findPopovers().at(1).props('target')()).toBe(findLabelButton(VIEW_MODE_BOARD).element);
    });

    it.each`
      scenario                       | props                                                    | dismisserProps
      ${'the board is not enabled'}  | ${{ showBoardPopover: true, isBoardEnabled: false }}     | ${{}}
      ${'the callout was dismissed'} | ${{ showBoardPopover: true }}                            | ${{ shouldShowCallout: false }}
      ${'the board view is active'}  | ${{ showBoardPopover: true, viewMode: VIEW_MODE_BOARD }} | ${{}}
    `('is hidden when $scenario', ({ props, dismisserProps }) => {
      createComponent({ props, dismisserProps });

      expect(findHotspot().exists()).toBe(false);
      expect(findPopovers()).toHaveLength(0);
    });

    it('does not dismiss the callout when the board view is already active', () => {
      const dismiss = jest.fn();
      createComponent({
        props: { showBoardPopover: true, viewMode: VIEW_MODE_BOARD },
        dismisserProps: { dismiss },
      });

      expect(dismiss).not.toHaveBeenCalled();
    });

    it('dismisses the callout and emits when the board button is clicked', () => {
      const dismiss = jest.fn();
      createComponent({ props: { showBoardPopover: true }, dismisserProps: { dismiss } });

      findLabelButton(VIEW_MODE_BOARD).vm.$emit('click');

      expect(dismiss).toHaveBeenCalledTimes(1);
      expect(wrapper.emitted('toggle-view-mode')).toEqual([[VIEW_MODE_BOARD]]);
    });

    it('keeps the callout when another view mode is clicked', () => {
      const dismiss = jest.fn();
      createComponent({ props: { showBoardPopover: true }, dismisserProps: { dismiss } });

      findLabelButton(VIEW_MODE_LIST).vm.$emit('click');

      expect(dismiss).not.toHaveBeenCalled();
    });

    it('does not dismiss the callout when the popover is not shown', () => {
      const dismiss = jest.fn();
      createComponent({ dismisserProps: { dismiss } });

      findLabelButton(VIEW_MODE_BOARD).vm.$emit('click');

      expect(dismiss).not.toHaveBeenCalled();
    });
  });

  describe('board view popover after the end date', () => {
    useFakeDate(2027, 0, 2);

    it('is hidden', () => {
      createComponent({ props: { showBoardPopover: true } });

      expect(wrapper.findComponent(WorkItemBoardViewPopover).exists()).toBe(false);
    });
  });
});
