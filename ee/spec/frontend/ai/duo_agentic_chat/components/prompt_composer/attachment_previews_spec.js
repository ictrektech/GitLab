import { GlButton } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import AttachmentPreviews from 'ee/ai/duo_agentic_chat/components/prompt_composer/attachment_previews.vue';

describe('AttachmentPreviews', () => {
  let wrapper;

  const attachments = [
    {
      id: 'a-1',
      filename: 'diagram.png',
      mimeType: 'image/png',
      byteSize: 2048,
      previewUrl: 'data:image/png;base64,AAA',
    },
    {
      id: 'a-2',
      filename: 'photo.jpeg',
      mimeType: 'image/jpeg',
      byteSize: 1024 * 1024,
      previewUrl: 'data:image/jpeg;base64,BBB',
    },
  ];

  const createComponent = (propsData = {}) => {
    wrapper = mountExtended(AttachmentPreviews, {
      propsData: { attachments, ...propsData },
    });
  };

  const findList = () => wrapper.findByTestId('attachment-previews');
  const findPreviews = () => wrapper.findAllByTestId('attachment-preview');
  const findRemoveButtons = () => wrapper.findAllComponents(GlButton);
  const findChips = () => wrapper.findAllByTestId('attachment-chip');

  it('renders nothing when there are no attachments', () => {
    createComponent({ attachments: [] });

    expect(findList().exists()).toBe(false);
  });

  it('renders one preview per attachment', () => {
    createComponent();

    expect(findPreviews()).toHaveLength(2);
  });

  it('renders each thumbnail, named and sized in its tooltip', () => {
    createComponent();

    const img = findPreviews().at(0).find('img');

    // Asserted on the DOM property rather than the attribute: Vue 3 sets `src` as a
    // property on an <img>, so `attributes()` never sees it.
    expect(img.element.src).toBe('data:image/png;base64,AAA');
    expect(img.attributes('alt')).toBe('diagram.png (2.00 KiB)');
    expect(findChips().at(0).find('img').attributes('title')).toBe('diagram.png (2.00 KiB)');
    expect(findChips().at(1).find('img').attributes('title')).toBe('photo.jpeg (1.00 MiB)');
  });

  it('emits `remove` with the attachment id', () => {
    createComponent();

    findRemoveButtons().at(1).vm.$emit('click');

    expect(wrapper.emitted('remove')).toEqual([['a-2']]);
  });

  it('gives each remove button an accessible label naming its file', () => {
    createComponent();

    expect(findRemoveButtons().at(0).attributes('aria-label')).toBe('Remove diagram.png');
  });

  it.each([true, false])('passes disabled=%p through to the remove buttons', (disabled) => {
    createComponent({ disabled });

    expect(findRemoveButtons().at(0).props('disabled')).toBe(disabled);
  });
});
