import { GlButton, GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import AttachmentChip from 'ee/ai/duo_agentic_chat/components/prompt_composer/attachment_chip.vue';

describe('AttachmentChip', () => {
  let wrapper;

  const attachment = {
    id: 'a-1',
    filename: 'diagram.png',
    mimeType: 'image/png',
    byteSize: 2048,
    previewUrl: 'data:image/png;base64,AAA',
  };

  const createComponent = (propsData = {}) => {
    wrapper = mountExtended(AttachmentChip, {
      propsData: { attachment, ...propsData },
    });
  };

  const findThumbnail = () => wrapper.findByTestId('attachment-thumbnail');
  const findIcon = () =>
    wrapper.findAllComponents(GlIcon).filter((icon) => icon.props('name') === 'doc-image');
  const findRemoveButton = () => wrapper.findComponent(GlButton);

  it('shows the thumbnail described by the filename and size', () => {
    createComponent();

    // Asserted on the DOM property rather than the attribute: Vue 3 sets `src` as a
    // property on an <img>, so `attributes()` never sees it.
    expect(findThumbnail().element.src).toBe('data:image/png;base64,AAA');
    expect(findThumbnail().attributes('alt')).toBe('diagram.png (2.00 KiB)');
    expect(findIcon()).toHaveLength(0);
  });

  // The tile carries no text, so the name and size live in its tooltip (and alt).
  it('names the file and its size in a tooltip', () => {
    createComponent();

    expect(findThumbnail().attributes('title')).toBe('diagram.png (2.00 KiB)');
  });

  it('describes the remove button in a tooltip', () => {
    createComponent();

    expect(findRemoveButton().attributes('title')).toBe('Remove');
  });

  it('emits `remove` with the attachment id', () => {
    createComponent();

    findRemoveButton().vm.$emit('click');

    expect(wrapper.emitted('remove')).toEqual([['a-1']]);
  });

  it('labels the remove button with the file it removes', () => {
    createComponent();

    expect(wrapper.findByRole('button', { name: 'Remove diagram.png' }).exists()).toBe(true);
  });

  it.each([true, false])('passes disabled=%p through to the remove button', (disabled) => {
    createComponent({ disabled });

    expect(findRemoveButton().props('disabled')).toBe(disabled);
  });

  // Every sink is an attribute, which Vue sets as text, so escaping would show `&amp;`.
  it('keeps HTML characters in the filename literal', () => {
    createComponent({ attachment: { ...attachment, filename: 'A&B <1>.png' } });

    expect(findThumbnail().attributes('title')).toBe('A&B <1>.png (2.00 KiB)');
    expect(findThumbnail().attributes('alt')).toBe('A&B <1>.png (2.00 KiB)');
    expect(findRemoveButton().attributes('aria-label')).toBe('Remove A&B <1>.png');
  });

  describe('view only', () => {
    beforeEach(() => {
      createComponent({ viewOnly: true });
    });

    it('drops the remove button', () => {
      expect(wrapper.findByRole('button').exists()).toBe(false);
      expect(findRemoveButton().exists()).toBe(false);
    });

    it('still shows the thumbnail', () => {
      expect(findThumbnail().attributes('alt')).toBe('diagram.png (2.00 KiB)');
    });
  });

  // What a reloaded turn has of a file: a name and a type, with no bytes behind them.
  describe('for a reference without preview or size', () => {
    beforeEach(() => {
      createComponent({
        attachment: { id: 'attachment-1', filename: 'diagram.png', mimeType: 'image/png' },
      });
    });

    it('shows a generic image in place of the thumbnail, still named for assistive tech', () => {
      expect(findThumbnail().exists()).toBe(false);
      expect(findIcon()).toHaveLength(1);
      expect(wrapper.findByRole('img', { name: 'diagram.png' }).exists()).toBe(true);
    });

    it('names only the file in the tooltip', () => {
      expect(wrapper.findByRole('img', { name: 'diagram.png' }).attributes('title')).toBe(
        'diagram.png',
      );
    });
  });
});
