import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import FileAttachments from 'ee/ai/duo_agentic_chat/components/prompt_composer/file_attachments.vue';
import AttachmentPreviews from 'ee/ai/duo_agentic_chat/components/prompt_composer/attachment_previews.vue';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
import { readFileAsDataURL } from '~/lib/utils/file_utility';

// Stubbed so the base64 payload is deterministic rather than depending on jsdom's
// FileReader actually decoding the synthetic Blobs below.
jest.mock('~/lib/utils/file_utility');

const BASE64 = 'aGVsbG8=';

const createImageFile = ({ name = 'shot.png', type = 'image/png', size = 1024 } = {}) => {
  const file = new File(['x'], name, { type });
  // `size` is read-only on File, so it is redefined rather than passed in.
  Object.defineProperty(file, 'size', { value: size });
  return file;
};

describe('FileAttachments', () => {
  let wrapper;

  const createComponent = ({
    attachments = [],
    disabled = false,
    enabled = true,
    ...options
  } = {}) => {
    wrapper = mountExtended(FileAttachments, {
      propsData: { attachments, disabled },
      provide: { glFeatures: { dapWebChatFileAttachments: enabled } },
      ...options,
    });
  };

  const findRoot = () => wrapper.findByTestId('file-attachments');
  const findFileInput = () => wrapper.findByTestId('attachment-file-input');
  const findPreviews = () => wrapper.findComponent(AttachmentPreviews);
  // The notices the composer would show after the latest `errors` event.
  const lastErrors = () => wrapper.emitted('errors')?.at(-1)?.[0] ?? [];

  // jsdom does not let a FileList be assigned to a file input, so `files` is redefined.
  const attach = async (files) => {
    Object.defineProperty(findFileInput().element, 'files', { value: files, configurable: true });
    await findFileInput().trigger('change');
    await waitForPromises();
  };

  // Paste and drop have no DOM route here: the composer owns those listeners and
  // calls these methods through its $refs, so the specs call them the same way.
  const paste = async (files) => {
    const event = { clipboardData: { files }, preventDefault: jest.fn() };
    wrapper.vm.onPaste(event);
    await waitForPromises();
    return event;
  };

  const drop = (files) => wrapper.vm.addFiles(files, { method: 'drag_and_drop' });

  // What the parent would hold after acting on the `add` events emitted so far.
  const addedAttachments = () => (wrapper.emitted('add') ?? []).flatMap(([batch]) => batch);

  beforeEach(() => {
    readFileAsDataURL.mockResolvedValue(`data:image/png;base64,${BASE64}`);
  });

  describe('picking files', () => {
    it('opens the file picker when the composer requests it', () => {
      createComponent();
      const clickSpy = jest.spyOn(findFileInput().element, 'click');

      wrapper.vm.openFilePicker();

      expect(clickSpy).toHaveBeenCalled();
    });

    it('restricts the picker to the supported image types', () => {
      createComponent();

      expect(findFileInput().attributes('accept')).toBe('image/png,image/jpeg,image/webp');
      expect(findFileInput().attributes('multiple')).toBeDefined();
    });
  });

  describe('previews', () => {
    it('hands the attachments it was given to the previews', () => {
      const attachments = [
        { id: 'a-1', filename: 'a.png', byteSize: 1 },
        { id: 'a-2', filename: 'b.png', byteSize: 2 },
      ];
      createComponent({ attachments });

      expect(findPreviews().props('attachments')).toEqual(attachments);
    });

    // The draft owns the attachments, so removal is a request rather than a local edit.
    it('asks for a removal when the preview requests one', () => {
      createComponent({ attachments: [{ id: 'a-1', filename: 'a.png', byteSize: 1 }] });

      findPreviews().vm.$emit('remove', 'a-1');

      expect(wrapper.emitted('remove')).toEqual([['a-1']]);
    });

    it('disables the previews when attaching is not allowed', () => {
      createComponent({ disabled: true });

      expect(findPreviews().props('disabled')).toBe(true);
    });
  });

  describe('accepting files', () => {
    it('offers the accepted files to the composer', async () => {
      createComponent();

      await attach([createImageFile({ name: 'a.png' }), createImageFile({ name: 'b.png' })]);

      expect(addedAttachments().map((a) => a.filename)).toEqual(['a.png', 'b.png']);
    });

    it('says nothing when every file was rejected', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('counts the attachments it already has against the limits', async () => {
      // Five is the cap, so a sixth has nowhere to go.
      const existing = Array.from({ length: 5 }, (_, i) => ({
        id: `a-${i}`,
        filename: `${i}.png`,
        byteSize: 1,
      }));
      createComponent({ attachments: existing });

      await attach([createImageFile({ name: 'sixth.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
      expect(lastErrors()[0]).toContain('Uploads limited to 5 files');
    });
  });

  describe('errors', () => {
    it('reports a rejected file to the composer', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      expect(lastErrors()).toHaveLength(1);
      expect(lastErrors()[0]).toContain('notes.pdf was not attached');
    });

    it('does not render the notices itself', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      expect(wrapper.findByTestId('attachment-error').exists()).toBe(false);
    });

    it('clears the notices of the previous batch once a batch goes through', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);
      await attach([createImageFile({ name: 'good.png' })]);

      expect(lastErrors()).toEqual([]);
    });

    it('still accepts the usable files from a mixed batch', async () => {
      createComponent();

      await attach([
        createImageFile({ name: 'good.png' }),
        createImageFile({ name: 'bad.pdf', type: 'application/pdf' }),
      ]);

      expect(addedAttachments().map((a) => a.filename)).toEqual(['good.png']);
      expect(lastErrors()).toHaveLength(1);
    });

    // The notices are keyed by their text, so a repeat would collide as a key and
    // dismiss with its twin. Pasted images share a generated filename, so a batch
    // can produce the same message twice.
    it('reports one notice when two files are rejected identically', async () => {
      createComponent();
      const rejected = () => createImageFile({ name: 'image-1.pdf', type: 'application/pdf' });

      await attach([rejected(), rejected()]);

      expect(lastErrors()).toHaveLength(1);
    });
  });

  describe('pasting', () => {
    it('takes a pasted image and stops the default paste', async () => {
      createComponent();

      const event = await paste([createImageFile({ name: 'shot.png' })]);

      expect(event.preventDefault).toHaveBeenCalled();
      expect(addedAttachments()).toHaveLength(1);
    });

    it('leaves a text-only paste alone', async () => {
      createComponent();

      const event = await paste([]);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    // Rich text can carry a file alongside the text. Claiming that paste would
    // lose the text, which is worse than not taking a file we cannot use anyway.
    it('leaves a paste carrying no supported image alone', async () => {
      createComponent();

      const event = await paste([createImageFile({ name: 'a.pdf', type: 'application/pdf' })]);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    it('reports an unsupported file pasted alongside an image', async () => {
      createComponent();

      await paste([
        createImageFile({ name: 'shot.png' }),
        createImageFile({ name: 'a.pdf', type: 'application/pdf' }),
      ]);

      expect(addedAttachments()).toHaveLength(1);
      expect(lastErrors()[0]).toContain('a.pdf was not attached');
    });
  });

  // Every route a file can take is refused, rather than only the removal buttons being
  // disabled, which would leave the user holding an attachment they cannot take back.
  describe('when disabled', () => {
    it('ignores files pushed at it', async () => {
      createComponent({ disabled: true });

      await drop([createImageFile({ name: 'a.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('does not open the file picker', () => {
      createComponent({ disabled: true });
      const clickSpy = jest.spyOn(findFileInput().element, 'click');

      wrapper.vm.openFilePicker();

      expect(clickSpy).not.toHaveBeenCalled();
    });

    it('leaves a pasted image to the browser', async () => {
      createComponent({ disabled: true });

      const event = await paste([createImageFile({ name: 'a.png' })]);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    // The draft can outlive the chat becoming unavailable, and what it is holding
    // still has to be visible.
    it('keeps showing the attachments it already has', () => {
      createComponent({ disabled: true, attachments: [{ id: 'a-1', filename: 'a.png' }] });

      expect(findPreviews().props('attachments')).toHaveLength(1);
    });
  });

  describe('when dapWebChatFileAttachments is disabled', () => {
    it('renders nothing at all', () => {
      createComponent({ enabled: false });

      expect(findRoot().exists()).toBe(false);
      expect(findFileInput().exists()).toBe(false);
    });

    it('ignores files pushed at it', async () => {
      createComponent({ enabled: false });

      await drop([createImageFile({ name: 'a.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('leaves a pasted image to the browser', async () => {
      createComponent({ enabled: false });

      const event = await paste([createImageFile({ name: 'a.png' })]);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });
  });

  describe('tracking', () => {
    beforeEach(() => {
      jest.spyOn(EventsTracker, 'trackAttachFile');
      jest.spyOn(EventsTracker, 'trackRejectFileAttachment');
    });

    it('tracks each file attached from the picker', async () => {
      createComponent();

      await attach([createImageFile(), createImageFile({ type: 'image/webp', size: 7 })]);

      expect(EventsTracker.trackAttachFile).toHaveBeenCalledTimes(2);
      expect(EventsTracker.trackAttachFile).toHaveBeenCalledWith({
        method: 'plus_menu',
        mimeType: 'image/webp',
        byteSize: 7,
      });
    });

    it('tracks a pasted file', async () => {
      createComponent();

      await paste([createImageFile()]);

      expect(EventsTracker.trackAttachFile).toHaveBeenCalledWith(
        expect.objectContaining({ method: 'paste' }),
      );
    });

    it('tracks a dropped file', async () => {
      createComponent();

      await drop([createImageFile()]);

      expect(EventsTracker.trackAttachFile).toHaveBeenCalledWith(
        expect.objectContaining({ method: 'drag_and_drop' }),
      );
    });

    it('still attaches a file added without a method', async () => {
      createComponent();

      await wrapper.vm.addFiles([createImageFile({ name: 'a.png' })]);

      expect(addedAttachments().map((a) => a.filename)).toEqual(['a.png']);
      expect(EventsTracker.trackAttachFile).toHaveBeenCalledWith(
        expect.objectContaining({ method: undefined }),
      );
    });

    it('tracks each rejection with its reason, not its filename', async () => {
      createComponent();

      await drop([createImageFile({ name: 'secret.pdf', type: 'application/pdf' })]);

      expect(EventsTracker.trackAttachFile).not.toHaveBeenCalled();
      expect(EventsTracker.trackRejectFileAttachment).toHaveBeenCalledWith({
        method: 'drag_and_drop',
        reason: 'unsupported_type',
        count: 1,
      });
    });

    it('tracks nothing when attaching is disabled', async () => {
      createComponent({ disabled: true });

      await attach([createImageFile()]);

      expect(EventsTracker.trackAttachFile).not.toHaveBeenCalled();
      expect(EventsTracker.trackRejectFileAttachment).not.toHaveBeenCalled();
    });
  });
});
