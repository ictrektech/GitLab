import { nextTick } from 'vue';
import { GlAnimatedUploadIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import AttachmentDropZone from 'ee/ai/duo_agentic_chat/components/attachment_drop_zone.vue';

// jsdom has no DragEvent, so a plain event carries a hand-rolled `dataTransfer`.
// `items` is what browsers expose mid-drag; `files` only arrives with the drop.
const dragEvent = (type, { types = ['Files'], items = [], files = [] } = {}) => {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, 'dataTransfer', { value: { types, items, files } });
  return event;
};

const fileItem = (type) => ({ kind: 'file', type });

const PNG = [fileItem('image/png')];
const PDF = [fileItem('application/pdf')];

describe('AttachmentDropZone', () => {
  let wrapper;

  const createComponent = ({ disabled = false, enabled = true } = {}) => {
    wrapper = mountExtended(AttachmentDropZone, {
      propsData: { disabled },
      provide: { glFeatures: { dapWebChatFileAttachments: enabled } },
      slots: { default: '<p data-testid="inside">chat</p>' },
      // Attached so that events dispatched inside the zone reach `document`, which is
      // where the component listens.
      attachTo: document.body,
    });
  };

  const findOverlay = () => wrapper.findByTestId('attachment-drop-overlay');
  const findInside = () => wrapper.findByTestId('inside');

  const dragOver = async (target, options) => {
    target.dispatchEvent(dragEvent('dragover', options));
    await nextTick();
  };
  const dragOverPage = (options) => dragOver(document.body, options);
  const dragOverChat = (options) => dragOver(findInside().element, options);

  describe('while a supported file is dragged', () => {
    it('shows nothing before any drag', () => {
      createComponent();

      expect(findOverlay().exists()).toBe(false);
    });

    it('invites a drop when the file is anywhere in the page', async () => {
      createComponent();

      await dragOverPage({ items: PNG });

      expect(findOverlay().text()).toContain('Drop to add file');
      expect(findOverlay().findComponent(GlAnimatedUploadIcon).exists()).toBe(true);
      expect(findOverlay().find('.gl-bg-strong').exists()).toBe(true);
    });

    it('highlights the chat when the file is over it', async () => {
      createComponent();

      await dragOverChat({ items: PNG });

      expect(findOverlay().text()).toContain('Drop to add file');
      expect(findOverlay().find('.gl-bg-feedback-info').exists()).toBe(true);
    });

    it('follows the file as it moves between the page and the chat', async () => {
      createComponent();

      await dragOverPage({ items: PNG });
      await dragOverChat({ items: PNG });
      expect(findOverlay().find('.gl-bg-feedback-info').exists()).toBe(true);

      await dragOverPage({ items: PNG });
      expect(findOverlay().find('.gl-bg-strong').exists()).toBe(true);
    });
  });

  describe('while an unsupported file is dragged', () => {
    it('shows nothing when the file is elsewhere in the page', async () => {
      createComponent();

      await dragOverPage({ items: PDF });

      expect(findOverlay().exists()).toBe(false);
    });

    it('explains what the chat takes when the file is over it', async () => {
      createComponent();

      await dragOverChat({ items: PDF });

      expect(findOverlay().text()).toContain('File type not supported');
      expect(findOverlay().text()).toContain('Supported formats: PNG, JPEG, WebP');
      expect(findOverlay().text()).toContain('File limit: 2 MiB');
      expect(findOverlay().find('.gl-bg-feedback-danger').exists()).toBe(true);
    });

    // A .dmg on macOS, or a folder, reports an empty type. The supported images
    // always carry one, so an empty type cannot be one of them.
    it('turns away a file of unknown type', async () => {
      createComponent();

      await dragOverChat({ items: [fileItem('')] });

      expect(findOverlay().find('.gl-bg-feedback-danger').exists()).toBe(true);
    });

    // One usable file is enough; the rest are reported per file on drop.
    it('treats a mixed batch as supported', async () => {
      createComponent();

      await dragOverChat({ items: [...PDF, ...PNG] });

      expect(findOverlay().find('.gl-bg-feedback-info').exists()).toBe(true);
    });
  });

  describe('ending the drag', () => {
    it('clears once the browser stops reporting the drag', async () => {
      createComponent();
      await dragOverChat({ items: PNG });

      jest.runOnlyPendingTimers();
      await nextTick();

      expect(findOverlay().exists()).toBe(false);
    });

    it('stays up while the browser keeps reporting the drag', async () => {
      createComponent();
      await dragOverChat({ items: PNG });

      jest.advanceTimersByTime(800);
      await dragOverChat({ items: PNG });
      jest.advanceTimersByTime(800);
      await nextTick();

      expect(findOverlay().exists()).toBe(true);
    });

    // Capture phase on `document`: a drop zone elsewhere that stops propagation
    // must not strand the overlay.
    it('clears on a drop anywhere in the page, even one that stops propagating', async () => {
      createComponent();
      await dragOverPage({ items: PNG });
      const sink = document.createElement('div');
      document.body.appendChild(sink);
      sink.addEventListener('drop', (event) => event.stopPropagation());

      sink.dispatchEvent(dragEvent('drop'));
      await nextTick();

      expect(findOverlay().exists()).toBe(false);
      sink.remove();
    });
  });

  describe('dropping on the chat', () => {
    it('lets the browser know a drop is welcome', () => {
      createComponent();
      const event = dragEvent('dragover', { items: PNG });

      findInside().element.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
    });

    // Otherwise the tab navigates to the file; the composer reports the rejection.
    it('lets the browser know a drop of an unsupported file is welcome too', () => {
      createComponent();
      const event = dragEvent('dragover', { items: PDF });

      findInside().element.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
    });

    it('hands the dropped files over and clears the overlay', async () => {
      createComponent();
      await dragOverChat({ items: PNG });
      const file = new File(['x'], 'shot.png', { type: 'image/png' });
      const event = dragEvent('drop', { files: [file] });

      findInside().element.dispatchEvent(event);
      await nextTick();

      expect(event.defaultPrevented).toBe(true);
      expect(wrapper.emitted('drop')).toEqual([[[file]]]);
      expect(findOverlay().exists()).toBe(false);
    });

    it('ignores a drop of something other than files', () => {
      createComponent();
      const event = dragEvent('drop', { types: ['text/plain'] });

      findInside().element.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(false);
      expect(wrapper.emitted('drop')).toBeUndefined();
    });
  });

  describe('when the chat cannot take files', () => {
    describe.each`
      reason                       | options
      ${'the chat is disabled'}    | ${{ disabled: true }}
      ${'the feature flag is off'} | ${{ enabled: false }}
    `('because $reason', ({ options }) => {
      it('shows no overlay', async () => {
        createComponent(options);

        await dragOverChat({ items: PNG });

        expect(findOverlay().exists()).toBe(false);
      });

      it('leaves a drop to the browser', () => {
        createComponent(options);
        const event = dragEvent('drop', { files: [new File(['x'], 'a.png')] });

        findInside().element.dispatchEvent(event);

        expect(event.defaultPrevented).toBe(false);
        expect(wrapper.emitted('drop')).toBeUndefined();
      });
    });
  });

  it('stops listening once destroyed', async () => {
    createComponent();
    const removeSpy = jest.spyOn(document, 'removeEventListener');

    wrapper.destroy();
    await dragOverPage({ items: PNG });

    expect(removeSpy).toHaveBeenCalledWith('dragover', expect.any(Function), true);
    expect(removeSpy).toHaveBeenCalledWith('drop', expect.any(Function), true);
  });
});
