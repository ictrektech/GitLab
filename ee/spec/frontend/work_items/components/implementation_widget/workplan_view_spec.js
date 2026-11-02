import { GlLoadingIcon } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkplanView from 'ee/work_items/components/implementation_widget/workplan_view.vue';
import WorkplanAvailabilityPopover from 'ee/work_items/components/implementation_widget/workplan_availability_popover.vue';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { destroyImageLightbox } from '~/behaviors/markdown/render_image_lightbox';

jest.mock('~/behaviors/markdown/render_gfm');
jest.mock('~/behaviors/markdown/render_image_lightbox');

const defaultProps = {
  generationDisabledReason: '',
  isLoading: false,
  canUpdate: true,
  savedContent: '',
  savedContentHtml: '',
};

describe('WorkplanView', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(WorkplanView, {
      propsData: {
        ...defaultProps,
        ...props,
      },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findEmptyState = () => wrapper.findByTestId('workplan-empty-state');
  const findEmptyStateComponent = () => wrapper.findComponentByTestId('workplan-empty-state');
  const findGenerateButton = () => wrapper.findComponentByTestId('panel-generate-button');
  const findCreateManuallyButton = () =>
    wrapper.findComponentByTestId('panel-create-manually-button');
  const findRenderedMarkdown = () => wrapper.findByTestId('workplan-rendered');
  const findAvailabilityPopover = () => wrapper.findComponent(WorkplanAvailabilityPopover);

  describe('when generation is unavailable', () => {
    beforeEach(() => {
      createComponent({
        generationDisabledReason: "Workplan generation isn't turned on for this project.",
      });
    });

    it('disables Generate and leaves manual creation available', () => {
      expect(wrapper.findComponentByTestId('panel-generate-button').props()).toMatchObject({
        disabled: true,
        accessibleDisabled: true,
      });
      expect(findCreateManuallyButton().props('disabled')).toBe(false);
    });

    it('explains why in the popover', () => {
      expect(findAvailabilityPopover().props('reason')).toBe(
        "Workplan generation isn't turned on for this project.",
      );
    });
  });

  describe('Duo action icons', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the Duo icon on Generate', () => {
      expect(findGenerateButton().props('icon')).toBe('tanuki-ai');
    });

    it('does not show the Duo icon on Create manually', () => {
      expect(findCreateManuallyButton().props('icon')).toBe('');
    });

    it('keeps the Duo icon on Generate when generation is unavailable', () => {
      createComponent({ generationDisabledReason: 'Unavailable.' });

      expect(findGenerateButton().props('icon')).toBe('tanuki-ai');
    });
  });

  describe('when generation is available', () => {
    beforeEach(() => {
      createComponent();
    });

    it('enables Generate', () => {
      expect(findGenerateButton().props('disabled')).toBe(false);
    });

    it('does not render the popover', () => {
      expect(findAvailabilityPopover().exists()).toBe(false);
    });
  });

  describe('while the plan content is loading', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: true, isLoading: true });
    });

    it('shows a loading icon instead of the empty state', () => {
      expect(findLoadingIcon().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when there is no saved content and the user can update', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: true });
    });

    it('shows the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findEmptyStateComponent().props('title')).toBe('Create a workplan');
    });

    it('renders both empty-state actions', () => {
      expect(findGenerateButton().exists()).toBe(true);
      expect(findCreateManuallyButton().exists()).toBe(true);
    });

    describe('when Generate is clicked', () => {
      beforeEach(() => {
        findGenerateButton().vm.$emit('click');
      });

      it('asks the parent to start a run', () => {
        expect(wrapper.emitted('generate')).toHaveLength(1);
      });
    });

    describe('when Create manually is clicked', () => {
      beforeEach(() => {
        findCreateManuallyButton().vm.$emit('click');
      });

      it('emits "start-edit"', () => {
        expect(wrapper.emitted('start-edit')).toHaveLength(1);
      });
    });
  });

  describe('when the user cannot update', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: false });
    });

    it('shows a read-only empty state with no actions', () => {
      expect(findEmptyState().text()).toContain("don't have permission");
      expect(findGenerateButton().exists()).toBe(false);
      expect(findCreateManuallyButton().exists()).toBe(false);
    });
  });

  describe('when saved content exists', () => {
    beforeEach(() => {
      createComponent({
        savedContent: 'Some plan content',
        savedContentHtml: '<p data-sourcepos="1:1-1:17">Some plan content</p>',
      });
    });

    it('renders the backend-rendered HTML inside a GLFM container', () => {
      expect(findRenderedMarkdown().exists()).toBe(true);
      expect(findRenderedMarkdown().classes()).toContain('md');
      expect(findRenderedMarkdown().element.innerHTML).toContain('Some plan content');
    });

    it('calls renderGFM on mount', async () => {
      await nextTick();

      expect(renderGFM).toHaveBeenCalledWith(findRenderedMarkdown().element);
    });

    describe('when the content changes', () => {
      it('calls renderGFM again', async () => {
        await nextTick();

        expect(renderGFM).toHaveBeenCalledTimes(1);

        await wrapper.setProps({ savedContentHtml: '<p>Updated plan</p>' });
        await nextTick();

        expect(renderGFM).toHaveBeenCalledTimes(2);
        expect(renderGFM).toHaveBeenNthCalledWith(2, findRenderedMarkdown().element);
      });
    });

    describe('when the component is destroyed', () => {
      it('tears down the image lightbox for the rendered content', () => {
        const contentElement = findRenderedMarkdown().element;

        expect(destroyImageLightbox).not.toHaveBeenCalled();

        wrapper.destroy();

        expect(destroyImageLightbox).toHaveBeenCalledTimes(1);
        expect(destroyImageLightbox).toHaveBeenCalledWith(contentElement);
      });
    });
  });

  describe('when a run is generating the plan', () => {
    beforeEach(() => {
      createComponent({ canUpdate: true, savedContent: '', isFlowActive: true });
    });

    it('hides Generate so the user cannot start a competing run', () => {
      expect(findGenerateButton().exists()).toBe(false);
    });

    it('keeps Create manually available', () => {
      expect(findCreateManuallyButton().exists()).toBe(true);
    });
  });

  describe('while a run is replacing a saved plan', () => {
    beforeEach(() => {
      createComponent({ canUpdate: true, savedContent: 'Old plan', isFlowActive: true });
    });

    it('hides the plan, so the panel does not read as though nothing is happening', () => {
      expect(findRenderedMarkdown().exists()).toBe(false);
    });

    it('shows a loader in its place', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });
});
