import { GlFormInput } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { visitUrl } from '~/lib/utils/url_utility';
import WorkItemTitleCell from '~/work_items/table/components/work_item_title_cell.vue';
import WorkItemTypeIcon from '~/work_items/components/work_item_type_icon.vue';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import { buildWorkItemNode } from '../../board/mock_data';
import { updateWorkItemMutationResponse } from '../../mock_data';

Vue.use(VueApollo);

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));

describe('WorkItemTitleCell', () => {
  let wrapper;

  const item = buildWorkItemNode(1, {
    title: 'Original title',
  });

  const defaultMutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
  const mockToast = { show: jest.fn() };

  afterEach(() => {
    wrapper?.destroy();
  });

  const findCellWrapper = () => wrapper.find('span');
  const findPencilButton = () => wrapper.findByTestId('edit-title-button');
  const findTitleInput = () => wrapper.findComponent(GlFormInput);
  const findTitleLink = () => wrapper.findByTestId('work-item-link');
  const findTitle = () => wrapper.findByTestId('work-item-title');
  const findConfidentialIcon = () => wrapper.findComponentByTestId('confidential-icon');
  const findWorkItemTypeIcon = () => wrapper.findComponent(WorkItemTypeIcon);

  const createComponent = ({
    props = {},
    mutationHandler = defaultMutationHandler,
    workItemFeaturesField = false,
  } = {}) => {
    const apolloProvider = createMockApollo([[updateWorkItemMutation, mutationHandler]]);

    wrapper = mountExtended(WorkItemTitleCell, {
      apolloProvider,
      directives: {
        TooltipOnTruncate: createMockDirective('tooltip-on-truncate'),
      },
      propsData: {
        item,
        ...props,
      },
      provide: {
        glFeatures: { workItemFeaturesField },
      },
      mocks: {
        $toast: mockToast,
      },
    });
  };

  describe('display mode', () => {
    beforeEach(() => {
      createComponent({ props: { detailPanelEnabled: true } });
    });

    it('renders the work item type icon', () => {
      expect(findWorkItemTypeIcon().props()).toMatchObject({
        workItemType: item.workItemType.name,
        typeIconName: item.workItemType.iconName,
      });
    });

    it('renders the title link', () => {
      expect(findTitleLink().exists()).toBe(true);
      expect(findTitleLink().attributes('href')).toBe(item.webPath);
    });

    it('renders the pencil button', () => {
      expect(findPencilButton().exists()).toBe(true);
      expect(findPencilButton().attributes('aria-label')).toBe('Edit title');
    });

    it('does not show the input field', () => {
      expect(findTitleInput().exists()).toBe(false);
    });
  });

  describe('title', () => {
    it('renders the title HTML without nested links', () => {
      createComponent({
        props: {
          item: buildWorkItemNode(1, {
            title: 'Fix `code` in #2',
            titleHtml: 'Fix <code>code</code> in <a href="/issues/2">#2</a>',
          }),
        },
      });

      expect(findTitle().element.innerHTML).toBe('Fix <code>code</code> in #2');
      expect(getBinding(findTitle().element, 'tooltip-on-truncate').value).toBe('Fix `code` in #2');
    });
  });

  describe('confidential icon', () => {
    it('is shown when the item is confidential', () => {
      createComponent({ props: { item: buildWorkItemNode(1, { confidential: true }) } });

      expect(findConfidentialIcon().props('name')).toBe('eye-slash');
      expect(findConfidentialIcon().attributes('aria-label')).toBe('Confidential');
    });

    it('is not shown when the item is not confidential', () => {
      createComponent();

      expect(findConfidentialIcon().exists()).toBe(false);
    });
  });

  describe('when the item has no work item type', () => {
    beforeEach(() => {
      createComponent({ props: { item: buildWorkItemNode(1, { workItemType: null }) } });
    });

    it('renders the title without the icon', () => {
      expect(findWorkItemTypeIcon().exists()).toBe(false);
      expect(findTitleLink().exists()).toBe(true);
    });
  });

  describe('entering edit mode', () => {
    beforeEach(async () => {
      createComponent({ props: { detailPanelEnabled: true } });
      await findPencilButton().trigger('click');
    });

    it('hides the title link and pencil button', () => {
      expect(findTitleLink().exists()).toBe(false);
      expect(findPencilButton().exists()).toBe(false);
    });

    it('shows the input field with current title', () => {
      expect(findTitleInput().exists()).toBe(true);
      expect(findTitleInput().props('value')).toBe(item.title);
    });

    it('does not open the panel when clicking inside the title input while editing', async () => {
      await findTitleInput().trigger('click');

      expect(wrapper.emitted('set-active-item')).toBeUndefined();
    });
  });

  describe('canceling edit', () => {
    beforeEach(async () => {
      createComponent({ props: { detailPanelEnabled: true } });
      await findPencilButton().trigger('click');
    });

    it('cancels on Escape key', async () => {
      await findTitleInput().setValue('Changed title');
      await findTitleInput().trigger('keydown', { key: 'Escape' });

      expect(findTitleInput().exists()).toBe(false);
      expect(findTitleLink().exists()).toBe(true);
    });

    it('prevents Escape key from propagating to parent handlers', async () => {
      const mockParentHandler = jest.fn();
      document.addEventListener('keydown', mockParentHandler);

      await findTitleInput().trigger('keydown', { key: 'Escape' });
      await nextTick();

      expect(mockParentHandler).not.toHaveBeenCalled();

      document.removeEventListener('keydown', mockParentHandler);
    });
  });

  describe('validation', () => {
    beforeEach(async () => {
      createComponent({ props: { detailPanelEnabled: true } });
      await findPencilButton().trigger('click');
    });

    it('invalidates empty title', async () => {
      await findTitleInput().setValue('');
      await nextTick();

      expect(findTitleInput().props('state')).toBe(false);
    });

    it('invalidates whitespace-only title', async () => {
      await findTitleInput().setValue('   ');
      await nextTick();

      expect(findTitleInput().props('state')).toBe(false);
    });

    it('validates non-empty title', async () => {
      await findTitleInput().setValue('Valid title');
      await nextTick();

      expect(findTitleInput().props('state')).toBe(true);
    });
  });

  describe('saving title', () => {
    beforeEach(() => {
      visitUrl.mockClear();
    });

    it('calls mutation with correct variables when saving via Enter key', async () => {
      const mutationHandler = jest.fn().mockResolvedValue({
        data: {
          workItemUpdate: {
            __typename: 'WorkItemUpdatePayload',
            errors: [],
            workItem: {
              ...item,
              title: 'New title',
            },
          },
        },
      });
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('New title');
      await nextTick();

      await findTitleInput().trigger('keydown', { key: 'Enter' });
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          title: 'New title',
        },
        useWorkItemFeatures: false,
      });
    });

    it('calls mutation with correct variables when saving via blur', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('Changed title');
      await nextTick();

      await findTitleInput().trigger('blur');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          title: 'Changed title',
        },
        useWorkItemFeatures: false,
      });
    });

    it('does not call mutation when title unchanged', async () => {
      const mutationHandler = jest.fn();
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await findTitleInput().trigger('keydown', { key: 'Enter' });
      await nextTick();

      expect(mutationHandler).not.toHaveBeenCalled();
      await waitForPromises();
    });

    it('stays in edit mode with the typed title and shows toast when mutation returns errors', async () => {
      const mutationHandler = jest.fn().mockResolvedValue({
        data: { workItemUpdate: { workItem: null, errors: ['Error updating title'] } },
      });
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('New title');
      await nextTick();

      await findTitleInput().trigger('keydown', { key: 'Enter' });
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalled();
      expect(mockToast.show).toHaveBeenCalledWith('Something went wrong while updating the title.');
      expect(findTitleInput().element.value).toBe('New title');
    });

    it('stays in edit mode with the typed title and shows toast when mutation throws error', async () => {
      const mutationHandler = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('New title');
      await nextTick();

      await findTitleInput().trigger('keydown', { key: 'Enter' });
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalled();
      expect(mockToast.show).toHaveBeenCalledWith('Something went wrong while updating the title.');
      expect(findTitleInput().element.value).toBe('New title');
    });

    it('does not save when Escape is pressed', async () => {
      const mutationHandler = jest.fn();
      createComponent({ mutationHandler, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('New title');
      await nextTick();

      await findTitleInput().trigger('keydown', { key: 'Escape' });
      await nextTick();

      expect(mutationHandler).not.toHaveBeenCalled();
    });
  });

  describe('when work_item_features_field is enabled', () => {
    it('sends useWorkItemFeatures: true', async () => {
      createComponent({ workItemFeaturesField: true, props: { detailPanelEnabled: true } });

      await findPencilButton().trigger('click');
      await nextTick();

      await findTitleInput().setValue('Changed title');
      await nextTick();

      await findTitleInput().trigger('blur');
      await waitForPromises();

      expect(defaultMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({ useWorkItemFeatures: true }),
      );
    });
  });

  describe('detail panel drawer opening', () => {
    describe('when detail panel is enabled', () => {
      beforeEach(() => {
        createComponent({ props: { detailPanelEnabled: true } });
      });

      it('opens the panel when cell is clicked', async () => {
        await findCellWrapper().trigger('click');

        expect(wrapper.emitted('set-active-item')).toEqual([[item]]);
      });

      it('prevents default navigation when opening the panel', () => {
        const event = new MouseEvent('click', { bubbles: true, cancelable: true });
        const preventDefaultSpy = jest.spyOn(event, 'preventDefault');

        findCellWrapper().element.dispatchEvent(event);

        expect(preventDefaultSpy).toHaveBeenCalled();
      });

      it.each(['metaKey', 'ctrlKey', 'shiftKey'])(
        'does not prevent default when %s is pressed, allowing browser to open in new tab',
        (modifier) => {
          const event = new MouseEvent('click', {
            bubbles: true,
            cancelable: true,
            [modifier]: true,
          });
          const preventDefaultSpy = jest.spyOn(event, 'preventDefault');

          findCellWrapper().element.dispatchEvent(event);

          expect(wrapper.emitted('set-active-item')).toBeUndefined();
          expect(preventDefaultSpy).not.toHaveBeenCalled();
        },
      );
    });

    describe('when detail panel is disabled', () => {
      beforeEach(() => {
        createComponent({ props: { detailPanelEnabled: false } });
      });

      it('link works as a normal href link', () => {
        expect(findTitleLink().attributes('href')).toBe(item.webPath);
      });

      it('does not emit set-active-item or navigate on regular click', async () => {
        await findTitleLink().trigger('click');

        expect(wrapper.emitted('set-active-item')).toBeUndefined();
        expect(visitUrl).not.toHaveBeenCalled();
      });
    });

    describe('when the work item is already active', () => {
      beforeEach(() => {
        createComponent({ props: { detailPanelEnabled: true, isActive: true } });
      });

      it('closes the panel when cell is clicked again', async () => {
        await findCellWrapper().trigger('click');

        expect(wrapper.emitted('set-active-item')).toEqual([[null]]);
      });

      it('does not close the panel when clicking inside the title input while editing', async () => {
        await findPencilButton().trigger('click');
        await findTitleInput().trigger('click');

        expect(wrapper.emitted('set-active-item')).toEqual(undefined);
      });
    });
  });
});
