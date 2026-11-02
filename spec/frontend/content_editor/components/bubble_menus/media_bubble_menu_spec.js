import { GlLink, GlForm } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import BubbleMenu from '~/content_editor/components/bubble_menus/bubble_menu.vue';
import MediaBubbleMenu from '~/content_editor/components/bubble_menus/media_bubble_menu.vue';
import { stubComponent } from 'helpers/stub_component';
import { iframeProviders } from 'helpers/iframe_providers';
import { buildParagraphWithIframeEmbed } from 'helpers/iframe_embeds';
import eventHubFactory from '~/helpers/event_hub_factory';
import waitForPromises from 'helpers/wait_for_promises';
import Audio from '~/content_editor/extensions/audio';
import DrawioDiagram from '~/content_editor/extensions/drawio_diagram';
import Iframe from '~/content_editor/extensions/iframe';
import Image from '~/content_editor/extensions/image';
import Video from '~/content_editor/extensions/video';
import { createTestEditor, emitEditorEvent, createTransactionWithMeta } from '../../test_utils';
import {
  PROJECT_WIKI_ATTACHMENT_IMAGE_HTML,
  PROJECT_WIKI_ATTACHMENT_AUDIO_HTML,
  PROJECT_WIKI_ATTACHMENT_VIDEO_HTML,
  PROJECT_WIKI_ATTACHMENT_DRAWIO_DIAGRAM_HTML,
} from '../../test_constants';

const TIPTAP_AUDIO_HTML = `<p dir="auto"><span class="media-container audio-container"><audio src="https://gitlab.com/favicon.png" controls="true" data-setup="{}" data-title="gitlab favicon"></audio><a href="https://gitlab.com/favicon.png" class="with-attachment-icon">gitlab favicon</a></span></p>`;

const TIPTAP_DIAGRAM_HTML = `<p dir="auto"><img src="https://gitlab.com/favicon.png" alt="gitlab favicon"></p>`;

const TIPTAP_IMAGE_HTML = `<p dir="auto"><img src="https://gitlab.com/favicon.png" alt="gitlab favicon"></p>`;

const TIPTAP_VIDEO_HTML = `<p dir="auto"><span class="media-container video-container"><video src="https://gitlab.com/favicon.png" controls="true" data-setup="{}" data-title="gitlab favicon"></video><a href="https://gitlab.com/favicon.png" class="with-attachment-icon">gitlab favicon</a></span></p>`;

const TIPTAP_IFRAME_HTML = buildParagraphWithIframeEmbed({
  src: 'https://www.youtube.com/embed/abc',
  canonicalSrc: 'https://www.youtube.com/watch?v=abc',
  title: 'test-video',
  width: '560',
  height: '315',
}).outerHTML;

const createFakeEvent = () => ({ preventDefault: jest.fn(), stopPropagation: jest.fn() });

describe('content_editor/components/bubble_menus/media_bubble_menu', () => {
  let wrapper;
  let tiptapEditor;
  let contentEditor;
  let eventHub;

  const buildEditor = () => {
    tiptapEditor = createTestEditor({ extensions: [Image, Audio, Video, DrawioDiagram, Iframe] });
    contentEditor = {
      resolveUrl: jest.fn(),
      resolveEmbed: jest.fn(),
    };
    eventHub = eventHubFactory();
  };

  const buildWrapper = () => {
    wrapper = mountExtended(MediaBubbleMenu, {
      provide: {
        tiptapEditor,
        contentEditor,
        eventHub,
      },
      stubs: {
        BubbleMenu: stubComponent(BubbleMenu),
      },
    });
  };

  const findBubbleMenu = () => wrapper.findComponent(BubbleMenu);

  const showMenu = async () => {
    findBubbleMenu().vm.$emit('show');
    await emitEditorEvent({
      event: 'transaction',
      tiptapEditor,
      params: { transaction: createTransactionWithMeta() },
    });
    await waitForPromises();
  };

  describe.each`
    mediaType          | mediaHTML                                      | filePath                  | mediaOutputHTML
    ${'image'}         | ${PROJECT_WIKI_ATTACHMENT_IMAGE_HTML}          | ${'test-file.png'}        | ${TIPTAP_IMAGE_HTML}
    ${'drawioDiagram'} | ${PROJECT_WIKI_ATTACHMENT_DRAWIO_DIAGRAM_HTML} | ${'test-file.drawio.svg'} | ${TIPTAP_DIAGRAM_HTML}
    ${'audio'}         | ${PROJECT_WIKI_ATTACHMENT_AUDIO_HTML}          | ${'test-file.mp3'}        | ${TIPTAP_AUDIO_HTML}
    ${'video'}         | ${PROJECT_WIKI_ATTACHMENT_VIDEO_HTML}          | ${'test-file.mp4'}        | ${TIPTAP_VIDEO_HTML}
  `('$mediaType', ({ mediaType, mediaHTML, filePath, mediaOutputHTML }) => {
    const buildWrapperAndDisplayMenu = () => {
      buildWrapper();

      return showMenu();
    };

    const expectLinkButtonsToExist = (exist = true) => {
      expect(wrapper.findComponent(GlLink).exists()).toBe(exist);
      expect(wrapper.findByTestId('edit-media').exists()).toBe(exist);
    };

    beforeEach(() => {
      buildEditor();

      tiptapEditor
        .chain()
        .insertContent(mediaHTML)
        .setNodeSelection(1) // select the media
        .run();

      contentEditor.resolveUrl.mockResolvedValue(`/group1/project1/-/wikis/${filePath}`);
    });

    it('renders bubble menu component', async () => {
      await buildWrapperAndDisplayMenu();

      expect(findBubbleMenu().classes()).toEqual(['gl-rounded-lg', 'gl-bg-overlap', 'gl-shadow']);
    });

    it('shows a clickable link to the image', async () => {
      await buildWrapperAndDisplayMenu();

      const link = wrapper.findComponent(GlLink);
      expect(link.attributes()).toMatchObject({
        href: `/group1/project1/-/wikis/${filePath}`,
        'aria-label': filePath,
        target: '_blank',
      });
      expect(link.text()).toBe(filePath);
    });

    it('shows a loading percentage for a file being uploaded', async () => {
      jest.spyOn(tiptapEditor, 'isActive').mockImplementation((name) => name === mediaType);

      await buildWrapperAndDisplayMenu();

      const setUploadProgress = async (progress) => {
        const transaction = createTransactionWithMeta('uploadProgress', {
          uploading: 'file-123',
          progress,
        });
        await emitEditorEvent({ event: 'transaction', tiptapEditor, params: { transaction } });
      };

      tiptapEditor.chain().selectAll().updateAttributes(mediaType, { uploading: 'file-123' }).run();

      await emitEditorEvent({ event: 'selectionUpdate', tiptapEditor });

      expect(wrapper.findComponent(GlLink).exists()).toBe(false);
      expect(wrapper.text()).toContain('Uploading: 0%');

      await setUploadProgress(0.4);

      expect(wrapper.text()).toContain('Uploading: 40%');

      await setUploadProgress(0.7);
      expect(wrapper.text()).toContain('Uploading: 70%');

      await setUploadProgress(1);
      expect(wrapper.text()).toContain('Uploading: 100%');
    });

    describe('when BubbleMenu emits hidden event', () => {
      it('resets media bubble menu state', async () => {
        await buildWrapperAndDisplayMenu();

        // Switch to edit mode to access component state in form fields
        await wrapper.findComponentByTestId('edit-media').vm.$emit('click');

        const mediaSrcInput = wrapper.findComponentByTestId('media-src').vm.$el;
        const mediaAltInput = wrapper.findComponentByTestId('media-alt').vm.$el;

        expect(mediaSrcInput.value).not.toBe('');
        expect(mediaAltInput.value).not.toBe('');

        await wrapper.findComponent(BubbleMenu).vm.$emit('hidden');

        expect(mediaSrcInput.value).toBe('');
        expect(mediaAltInput.value).toBe('');
      });
    });

    describe('edit button', () => {
      let mediaSrcInput;
      let mediaAltInput;

      beforeEach(async () => {
        await buildWrapperAndDisplayMenu();

        await wrapper.findComponentByTestId('edit-media').vm.$emit('click');

        mediaSrcInput = wrapper.findComponentByTestId('media-src');
        mediaAltInput = wrapper.findComponentByTestId('media-alt');
      });

      it('hides the link and copy/edit/remove link buttons', () => {
        expectLinkButtonsToExist(false);
      });

      it('labels the alt text field as alt text', () => {
        expect(wrapper.find('label[for="media-alt"]').text()).toBe('Alt text');
      });

      it(`shows a form to edit the ${mediaType} src/alt`, () => {
        expect(wrapper.findComponent(GlForm).exists()).toBe(true);

        // Assert focus is managed correctly
        expect(mediaSrcInput.props('autofocus')).toBe(true);
        expect(mediaAltInput.props('autofocus')).toBe(false);

        // Assert input values are correct
        expect(mediaSrcInput.element.value).toBe(filePath);
        expect(mediaAltInput.element.value).toBe('test-file');
      });

      describe('after making changes in the form and clicking apply', () => {
        beforeEach(async () => {
          mediaSrcInput.setValue('https://gitlab.com/favicon.png');
          mediaAltInput.setValue('gitlab favicon');

          contentEditor.resolveUrl.mockResolvedValue('https://gitlab.com/favicon.png');

          await wrapper.findComponent(GlForm).vm.$emit('submit', createFakeEvent());
        });

        it(`updates prosemirror doc with new src to the ${mediaType}`, () => {
          expect(tiptapEditor.getHTML()).toBe(mediaOutputHTML);
        });

        it(`updates the link to the ${mediaType} in the bubble menu`, () => {
          const link = wrapper.findComponent(GlLink);
          expect(link.attributes()).toMatchObject({
            href: 'https://gitlab.com/favicon.png',
            'aria-label': 'https://gitlab.com/favicon.png',
            target: '_blank',
          });
          expect(link.text()).toBe('https://gitlab.com/favicon.png');
        });
      });

      describe('after making changes in the form and clicking cancel', () => {
        beforeEach(async () => {
          mediaSrcInput.setValue('https://gitlab.com/favicon.png');
          mediaAltInput.setValue('gitlab favicon');

          await wrapper.findComponentByTestId('cancel-editing-media').vm.$emit('click');
        });

        it('hides the form and shows the copy/edit/remove link buttons', () => {
          expectLinkButtonsToExist();
        });

        it(`resets the form with old values of the ${mediaType} from prosemirror`, async () => {
          // click edit once again to show the form back
          await wrapper.findComponentByTestId('edit-media').vm.$emit('click');

          mediaSrcInput = wrapper.findByTestId('media-src');
          mediaAltInput = wrapper.findByTestId('media-alt');

          expect(mediaSrcInput.element.value).toBe(filePath);
          expect(mediaAltInput.element.value).toBe('test-file');
        });
      });
    });
  });

  describe('iframe', () => {
    const findForm = () => wrapper.findComponent(GlForm);
    const findSrcInput = () => wrapper.findByTestId('media-src');
    const findAltLabel = () => wrapper.find('label[for="media-alt"]');
    const findInvalidFeedback = () => wrapper.find('.invalid-feedback');

    const startEditing = async () => {
      buildWrapper();
      await showMenu();

      await wrapper.findComponentByTestId('edit-media').vm.$emit('click');
    };

    const submitEmbedUrl = async (url) => {
      findSrcInput().setValue(url);

      await findForm().vm.$emit('submit', createFakeEvent());
      await waitForPromises();
    };

    beforeEach(() => {
      window.gon = {
        iframe_rendering_providers: iframeProviders(),
        features: { allowIframesInMarkdown: true },
      };

      buildEditor();

      tiptapEditor.chain().insertContent(TIPTAP_IFRAME_HTML).setNodeSelection(1).run();
    });

    it('does not show the embed URL', async () => {
      contentEditor.resolveUrl.mockResolvedValue('https://www.youtube.com/watch?v=abc');

      buildWrapper();
      await showMenu();

      expect(wrapper.findComponent(GlLink).exists()).toBe(false);
      expect(wrapper.findByTestId('edit-media').exists()).toBe(true);
    });

    describe('when editing', () => {
      beforeEach(async () => {
        await startEditing();
      });

      it('labels the alt text field as the title', () => {
        expect(findAltLabel().text()).toBe('Title');
      });

      describe('when the edited URL resolves to an embed', () => {
        beforeEach(async () => {
          contentEditor.resolveEmbed.mockResolvedValue({
            src: 'https://www.youtube.com/embed/xyz',
            providerId: 'youtube',
          });
          contentEditor.resolveUrl.mockClear();

          await submitEmbedUrl('https://www.youtube.com/watch?v=xyz');
        });

        it('resolves the URL as an embed, not as a URL', () => {
          expect(contentEditor.resolveEmbed).toHaveBeenCalledWith(
            'https://www.youtube.com/watch?v=xyz',
          );
          expect(contentEditor.resolveUrl).not.toHaveBeenCalled();
        });

        it('updates the node', () => {
          const { src, canonicalSrc, providerId } = tiptapEditor.getAttributes('iframe');

          expect(src).toBe('https://www.youtube.com/embed/xyz');
          expect(canonicalSrc).toBe('https://www.youtube.com/watch?v=xyz');
          expect(providerId).toBe('youtube');
        });

        it('closes the form', () => {
          expect(findForm().exists()).toBe(false);
        });
      });

      describe('when the edited URL resolves to another provider', () => {
        beforeEach(async () => {
          contentEditor.resolveEmbed.mockResolvedValue({
            src: 'https://embed.figma.com/design/xyz?embed-host=gitlab',
            providerId: 'figma',
          });

          await submitEmbedUrl('https://www.figma.com/design/xyz');
        });

        it('adopts that provider', () => {
          const { src, providerId } = tiptapEditor.getAttributes('iframe');

          expect(src).toBe('https://embed.figma.com/design/xyz?embed-host=gitlab');
          expect(providerId).toBe('figma');
        });
      });

      describe('#security: when the edited URL cannot be embedded', () => {
        beforeEach(async () => {
          contentEditor.resolveEmbed.mockResolvedValue(null);

          await submitEmbedUrl('https://evil.example.com/embed/xyz');
        });

        it('leaves the node untouched', () => {
          const { src, canonicalSrc, providerId } = tiptapEditor.getAttributes('iframe');

          expect(src).toBe('https://www.youtube.com/embed/abc');
          expect(canonicalSrc).toBe('https://www.youtube.com/watch?v=abc');
          expect(providerId).toBe('youtube');
        });

        it('keeps the form open with the entered URL', () => {
          expect(findForm().exists()).toBe(true);
          expect(findSrcInput().element.value).toBe('https://evil.example.com/embed/xyz');
        });

        it('names the allowed embed providers', () => {
          expect(findInvalidFeedback().text()).toBe(
            'Enter a URL from an allowed embed provider: YouTube or Figma.',
          );
        });

        describe('when the URL is changed', () => {
          beforeEach(async () => {
            await findSrcInput().setValue('https://www.youtube.com/watch?v=xyz');
          });

          it('clears the error', () => {
            expect(findInvalidFeedback().exists()).toBe(false);
          });
        });

        describe('when editing is cancelled and restarted', () => {
          beforeEach(async () => {
            await wrapper.findComponentByTestId('cancel-editing-media').vm.$emit('click');
            await wrapper.findComponentByTestId('edit-media').vm.$emit('click');
          });

          it('clears the error', () => {
            expect(findInvalidFeedback().exists()).toBe(false);
          });
        });
      });

      describe('when the URL changes while it resolves', () => {
        let resolveEmbed;

        beforeEach(async () => {
          contentEditor.resolveEmbed.mockReturnValue(
            new Promise((resolve) => {
              resolveEmbed = resolve;
            }),
          );

          await findSrcInput().setValue('https://www.youtube.com/watch?v=xyz');
          await findForm().vm.$emit('submit', createFakeEvent());

          await findSrcInput().setValue('https://www.figma.com/design/xyz');
          resolveEmbed({ src: 'https://www.youtube.com/embed/xyz', providerId: 'youtube' });
          await waitForPromises();
        });

        it('updates the node with the URL that was resolved', () => {
          const { src, canonicalSrc, providerId } = tiptapEditor.getAttributes('iframe');

          expect(src).toBe('https://www.youtube.com/embed/xyz');
          expect(canonicalSrc).toBe('https://www.youtube.com/watch?v=xyz');
          expect(providerId).toBe('youtube');
        });
      });
    });
  });
});
