import { GlCollapsibleListbox, GlLabel, GlPopover } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemLabelsCell from '~/work_items/table/components/work_item_labels_cell.vue';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import groupLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/group_labels.query.graphql';
import projectLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/project_labels.query.graphql';
import { buildWorkItemNode, buildLabelsWidget, mockLabels } from '../../board/mock_data';
import { updateWorkItemMutationResponse } from '../../mock_data';

Vue.use(VueApollo);

describe('WorkItemLabelsCell', () => {
  let wrapper;

  const mockLabel1 = mockLabels[0];
  const mockLabel2 = mockLabels[1];
  const mockLabel3 = {
    __typename: 'Label',
    id: 'gid://gitlab/Label/3',
    title: 'backend',
    description: 'Backend work',
    color: '#0000ff',
    textColor: '#ffffff',
  };

  const item = buildWorkItemNode(1, {
    title: 'Test work item',
    widgets: [buildLabelsWidget([mockLabel1, mockLabel2])],
  });

  const itemWithoutLabels = buildWorkItemNode(2, {
    widgets: [buildLabelsWidget([])],
  });

  const availableLabelsResponse = {
    data: {
      namespace: {
        id: 'gid://gitlab/Project/1',
        labels: {
          nodes: [mockLabel1, mockLabel2, mockLabel3],
        },
      },
    },
  };

  let defaultMutationHandler;
  let labelsQueryHandler;
  let mockToast;

  beforeEach(() => {
    defaultMutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
    labelsQueryHandler = jest.fn().mockResolvedValue(availableLabelsResponse);
    mockToast = { show: jest.fn() };
  });

  const findCellWrapper = () => wrapper.find('span');
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findDisplayLabels = () => wrapper.findAllByTestId('label-item');
  const findMoreLabelsButton = () => wrapper.findByTestId('more-labels-button');
  const findPopover = () => wrapper.findComponent(GlPopover);

  const createComponent = ({ props = {}, mutationHandler = defaultMutationHandler } = {}) => {
    const apolloProvider = createMockApollo([
      [updateWorkItemMutation, mutationHandler],
      [projectLabelsQuery, labelsQueryHandler],
      [groupLabelsQuery, labelsQueryHandler],
    ]);

    wrapper = mountExtended(WorkItemLabelsCell, {
      apolloProvider,
      propsData: {
        item,
        ...props,
      },
      provide: {
        glFeatures: { workItemFeaturesField: false },
        hasScopedLabelsFeature: false,
        isGroup: false,
        rootPageFullPath: 'group/project',
        workItemsListPath: '/group/project/-/work_items',
      },
      mocks: {
        $toast: mockToast,
      },
    });
  };

  describe('display mode', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders labels with correct props', () => {
      const labels = wrapper
        .findAllComponents(GlLabel)
        .filter((l) => l.attributes('data-testid') === 'label-item');
      expect(labels).toHaveLength(2);
      expect(labels.at(0).props()).toMatchObject({
        backgroundColor: mockLabel1.color,
        title: mockLabel1.title,
        description: mockLabel1.description,
      });
      expect(labels.at(1).props()).toMatchObject({
        backgroundColor: mockLabel2.color,
        title: mockLabel2.title,
        description: mockLabel2.description,
      });
    });

    it('does not show the listbox', () => {
      expect(findListbox().exists()).toBe(false);
    });

    it('clicking cell enters edit mode', async () => {
      await findCellWrapper().trigger('click');

      expect(findListbox().exists()).toBe(true);
      expect(findDisplayLabels()).toHaveLength(0);
    });
  });

  describe('when work item has no labels', () => {
    beforeEach(() => {
      createComponent({ props: { item: itemWithoutLabels } });
    });

    it('renders no labels', () => {
      expect(findDisplayLabels()).toHaveLength(0);
    });

    it('can still enter edit mode', async () => {
      await findCellWrapper().trigger('click');

      expect(findListbox().exists()).toBe(true);
    });
  });

  describe('clicking on labels', () => {
    it('does not enter edit mode when clicking on label itself', async () => {
      createComponent();
      const label = findDisplayLabels().at(0);

      await label.trigger('click');

      expect(findListbox().exists()).toBe(false);
    });
  });

  describe('entering edit mode', () => {
    beforeEach(async () => {
      createComponent();
      await findCellWrapper().trigger('click');
      await nextTick();
    });

    it('hides the display labels', () => {
      expect(findDisplayLabels()).toHaveLength(0);
    });

    it('shows listbox with correct configuration', () => {
      expect(findListbox().exists()).toBe(true);
      expect(findListbox().props()).toMatchObject({
        multiple: true,
        searchable: true,
        isCheckCentered: true,
        headerText: 'Select labels',
        resetButtonLabel: 'Clear',
      });
    });

    it('initializes listbox with current label selections', () => {
      expect(findListbox().props('selected')).toEqual([mockLabel1.id, mockLabel2.id]);
    });
  });

  describe('label search and fetching', () => {
    beforeEach(async () => {
      createComponent();
      await findCellWrapper().trigger('click');
      await nextTick();
    });

    it('fetches available labels when entering edit mode', async () => {
      findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(labelsQueryHandler).toHaveBeenCalledWith({
        fullPath: 'group/project',
        searchTerm: '',
      });
    });

    it('searches labels when typing', async () => {
      findListbox().vm.$emit('search', 'backend');
      await waitForPromises();

      expect(labelsQueryHandler).toHaveBeenCalledWith({
        fullPath: 'group/project',
        searchTerm: 'backend',
      });
    });

    it('uses group labels query when isGroup is true', async () => {
      wrapper.destroy();
      createComponent({ provide: { isGroup: true } });
      await findCellWrapper().trigger('click');
      await nextTick();

      findListbox().vm.$emit('shown');
      await waitForPromises();

      expect(labelsQueryHandler).toHaveBeenCalled();
    });
  });

  describe('when selecting and deselecting labels', () => {
    beforeEach(async () => {
      createComponent();
      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();
    });

    it('updates selection when selecting a new label', async () => {
      findListbox().vm.$emit('select', [mockLabel1.id, mockLabel2.id, mockLabel3.id]);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([
        mockLabel1.id,
        mockLabel2.id,
        mockLabel3.id,
      ]);
    });

    it('removes label when updating selection', async () => {
      findListbox().vm.$emit('select', [mockLabel2.id]);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([mockLabel2.id]);
    });

    it('clears all selections when clicking reset button', async () => {
      findListbox().vm.$emit('reset');
      await nextTick();

      expect(findListbox().props('selected')).toEqual([]);
    });
  });

  describe('when saving labels', () => {
    it('calls mutation with correct variables when adding labels', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      findListbox().vm.$emit('select', [mockLabel1.id, mockLabel2.id, mockLabel3.id]);
      await nextTick();

      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          labelsWidget: {
            addLabelIds: [mockLabel3.id],
            removeLabelIds: [],
          },
        },
        useWorkItemFeatures: false,
      });
    });

    it('calls mutation with correct variables when removing labels', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      findListbox().vm.$emit('select', [mockLabel1.id]);
      await nextTick();

      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          labelsWidget: {
            addLabelIds: [],
            removeLabelIds: [mockLabel2.id],
          },
        },
        useWorkItemFeatures: false,
      });
    });

    it('does not call mutation when labels unchanged', async () => {
      const mutationHandler = jest.fn();
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      findListbox().vm.$emit('hidden');
      await nextTick();

      expect(mutationHandler).not.toHaveBeenCalled();
    });

    it('calls mutation when labels change', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      // Select different labels (remove label2, add label3)
      findListbox().vm.$emit('select', [mockLabel1.id, mockLabel3.id]);
      await nextTick();

      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalled();
    });

    it('exits edit mode and shows toast when mutation returns errors', async () => {
      const mutationHandler = jest.fn().mockResolvedValue({
        data: { workItemUpdate: { workItem: null, errors: ['Error updating labels'] } },
      });
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      findListbox().vm.$emit('select', [mockLabel1.id]);
      await nextTick();

      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalled();
      expect(mockToast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the labels.',
      );
      expect(findListbox().exists()).toBe(false);
    });

    it('exits edit mode and shows toast when mutation throws error', async () => {
      const mutationHandler = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent({ mutationHandler });

      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();

      findListbox().vm.$emit('select', [mockLabel1.id]);
      await nextTick();

      findListbox().vm.$emit('hidden');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalled();
      expect(mockToast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the labels.',
      );
      expect(findListbox().exists()).toBe(false);
    });
  });

  describe('listbox items structure', () => {
    beforeEach(async () => {
      createComponent();
      await findCellWrapper().trigger('click');
      await nextTick();
      findListbox().vm.$emit('shown');
      await waitForPromises();
    });

    it('groups items into Selected and All sections when labels are selected', () => {
      const items = findListbox().props('items');
      expect(items).toHaveLength(2);
      expect(items[0].text).toBe('Selected');
      expect(items[0].options).toHaveLength(2);
      expect(items[1].text).toBe('All');
      expect(items[1].textSrOnly).toBe(true);
      expect(items[1].options).toHaveLength(3);
    });

    it('shows flat list when searching', async () => {
      findListbox().vm.$emit('search', 'backend');
      await nextTick();

      const items = findListbox().props('items');
      expect(Array.isArray(items)).toBe(true);
      expect(items.some((i) => i.text === 'Selected')).toBe(false);
    });
  });

  describe('toggle display', () => {
    it('shows current labels in toggle when editing', async () => {
      createComponent();
      await findCellWrapper().trigger('click');
      await nextTick();

      const toggleLabels = wrapper.findAllByTestId('toggle-label-item');
      expect(toggleLabels).toHaveLength(2);
    });

    it('shows no labels in toggle when item has no labels', async () => {
      createComponent({ props: { item: itemWithoutLabels } });
      await findCellWrapper().trigger('click');
      await nextTick();

      const toggleLabels = wrapper.findAllByTestId('toggle-label-item');
      expect(toggleLabels).toHaveLength(0);
    });
  });

  describe('showing more labels', () => {
    const mockLabel4 = {
      __typename: 'Label',
      id: 'gid://gitlab/Label/4',
      title: 'documentation',
      description: 'Documentation updates',
      color: '#00ff00',
      textColor: '#000000',
    };
    const mockLabel5 = {
      __typename: 'Label',
      id: 'gid://gitlab/Label/5',
      title: 'security',
      description: 'Security related',
      color: '#ff0000',
      textColor: '#ffffff',
    };

    const itemWithManyLabels = buildWorkItemNode(4, {
      widgets: [buildLabelsWidget([mockLabel1, mockLabel2, mockLabel3, mockLabel4, mockLabel5])],
    });

    it('shows only first 3 labels when there are more than 3', () => {
      createComponent({ props: { item: itemWithManyLabels } });

      expect(findDisplayLabels()).toHaveLength(3);
    });

    it('shows "+N more" button when there are more than 3 labels', () => {
      createComponent({ props: { item: itemWithManyLabels } });

      expect(findMoreLabelsButton().exists()).toBe(true);
      expect(findMoreLabelsButton().text()).toBe('+2');
    });

    it('does not show "+N more" button when there are 3 or fewer labels', () => {
      createComponent();

      expect(findMoreLabelsButton().exists()).toBe(false);
    });

    it('shows popover with hidden labels on hover', () => {
      createComponent({ props: { item: itemWithManyLabels } });

      const popover = findPopover();
      expect(popover.exists()).toBe(true);
      expect(popover.props('target')).toBe(`more-labels-${itemWithManyLabels.id}`);
      expect(popover.props('triggers')).toBe('hover focus');

      const popoverLabels = popover.findAllComponents(GlLabel);
      expect(popoverLabels).toHaveLength(2);
      expect(popoverLabels.at(0).props('title')).toBe(mockLabel4.title);
      expect(popoverLabels.at(1).props('title')).toBe(mockLabel5.title);
    });
  });
});
