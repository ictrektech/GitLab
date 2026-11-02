import { GlForm } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { iframeProviders } from 'helpers/iframe_providers';
import waitForPromises from 'helpers/wait_for_promises';
import BubbleMenu from '~/content_editor/components/bubble_menus/bubble_menu.vue';
import IframeInsertBubbleMenu from '~/content_editor/components/bubble_menus/iframe_insert_bubble_menu.vue';
import Iframe, { iframeInsertPluginKey } from '~/content_editor/extensions/iframe';
import eventHubFactory from '~/helpers/event_hub_factory';
import { createTestEditor } from '../../test_utils';

const YOUTUBE_URL = 'https://www.youtube.com/watch?v=xyz';
const YOUTUBE_EMBED_URL = 'https://www.youtube.com/embed/xyz';

const createFakeEvent = () => ({ preventDefault: jest.fn(), stopPropagation: jest.fn() });

describe('content_editor/components/bubble_menus/iframe_insert_bubble_menu', () => {
  let wrapper;
  let tiptapEditor;
  let contentEditor;

  const buildWrapper = () => {
    wrapper = mountExtended(IframeInsertBubbleMenu, {
      provide: {
        tiptapEditor,
        contentEditor,
        eventHub: eventHubFactory(),
      },
      stubs: {
        BubbleMenu: stubComponent(BubbleMenu),
      },
    });
  };

  const findBubbleMenu = () => wrapper.findComponent(BubbleMenu);
  const findForm = () => wrapper.findComponent(GlForm);
  const findSrcInput = () => wrapper.findByTestId('iframe-insert-src');
  const findAltInput = () => wrapper.findByTestId('iframe-insert-alt');
  const findInvalidFeedback = () => wrapper.find('.invalid-feedback');

  const insertRange = () => iframeInsertPluginKey.getState(tiptapEditor.state);
  const iframeNodes = () => {
    const nodes = [];
    tiptapEditor.state.doc.descendants((node) => {
      if (node.type.name === Iframe.name) nodes.push(node);
    });
    return nodes;
  };

  const submit = async ({ src = YOUTUBE_URL, alt = '' } = {}) => {
    await findSrcInput().setValue(src);
    await findAltInput().setValue(alt);

    await findForm().vm.$emit('submit', createFakeEvent());
    await waitForPromises();
  };

  beforeEach(() => {
    window.gon = {
      iframe_rendering_providers: iframeProviders(),
      features: { allowIframesInMarkdown: true },
    };

    tiptapEditor = createTestEditor({ extensions: [Iframe] });
    tiptapEditor.commands.setContent('<p>hello world</p>');
    tiptapEditor.commands.setTextSelection(6);

    contentEditor = { resolveEmbed: jest.fn() };

    buildWrapper();
  });

  describe('when no insert is open', () => {
    it('does not show', () => {
      expect(findBubbleMenu().props('shouldShow')({ state: tiptapEditor.state })).toBe(false);
    });
  });

  describe('when an insert is open', () => {
    beforeEach(() => {
      tiptapEditor.commands.insertIframe();
    });

    it('shows', () => {
      expect(findBubbleMenu().props('shouldShow')({ state: tiptapEditor.state })).toBe(true);
    });

    it('labels the fields', () => {
      expect(wrapper.find('label[for="iframe-insert-src"]').text()).toBe('URL');
      expect(wrapper.find('label[for="iframe-insert-alt"]').text()).toBe('Title');
    });

    it('names the form', () => {
      expect(findForm().attributes('aria-label')).toBe('Insert embedded content');
    });

    describe('when the URL resolves to an embed', () => {
      beforeEach(async () => {
        contentEditor.resolveEmbed.mockResolvedValue({
          src: YOUTUBE_EMBED_URL,
          providerId: 'youtube',
        });

        await submit({ alt: 'A video' });
      });

      it('resolves the entered URL', () => {
        expect(contentEditor.resolveEmbed).toHaveBeenCalledWith(YOUTUBE_URL);
      });

      it('inserts an iframe node at the insert', () => {
        const [node] = iframeNodes();

        expect(node.attrs).toMatchObject({
          src: YOUTUBE_EMBED_URL,
          canonicalSrc: YOUTUBE_URL,
          providerId: 'youtube',
          alt: 'A video',
        });
        expect(tiptapEditor.state.doc.resolve(6).nodeAfter).toBe(node);
      });

      it('closes the insert', () => {
        expect(insertRange()).toBeNull();
      });
    });

    describe('when no title is entered', () => {
      beforeEach(async () => {
        contentEditor.resolveEmbed.mockResolvedValue({
          src: YOUTUBE_EMBED_URL,
          providerId: 'youtube',
        });

        await submit();
      });

      it('inserts an iframe node without a title', () => {
        expect(iframeNodes()[0].attrs.alt).toBeNull();
      });
    });

    describe('#security: when the URL cannot be embedded', () => {
      beforeEach(async () => {
        contentEditor.resolveEmbed.mockResolvedValue(null);

        await submit({ src: 'https://evil.example.com/embed/xyz' });
      });

      it('does not insert an iframe node', () => {
        expect(iframeNodes()).toHaveLength(0);
      });

      it('keeps the insert open', () => {
        expect(insertRange()).toEqual({ from: 6, to: 6 });
      });

      it('names the allowed embed providers', () => {
        expect(findInvalidFeedback().text()).toBe(
          'Enter a URL from an allowed embed provider: YouTube or Figma.',
        );
      });

      describe('when the URL is changed', () => {
        beforeEach(async () => {
          await findSrcInput().setValue(YOUTUBE_URL);
        });

        it('clears the error', () => {
          expect(findInvalidFeedback().exists()).toBe(false);
        });
      });
    });

    describe('when the insert closes while the URL resolves', () => {
      let resolveEmbed;

      beforeEach(async () => {
        contentEditor.resolveEmbed.mockReturnValue(
          new Promise((resolve) => {
            resolveEmbed = resolve;
          }),
        );

        await findSrcInput().setValue(YOUTUBE_URL);
        await findForm().vm.$emit('submit', createFakeEvent());

        tiptapEditor.commands.setTextSelection(2);
        resolveEmbed({ src: YOUTUBE_EMBED_URL, providerId: 'youtube' });
        await waitForPromises();
      });

      it('does not insert an iframe node', () => {
        expect(iframeNodes()).toHaveLength(0);
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

        await findSrcInput().setValue(YOUTUBE_URL);
        await findForm().vm.$emit('submit', createFakeEvent());

        await findSrcInput().setValue('https://www.figma.com/design/xyz');
        resolveEmbed({ src: YOUTUBE_EMBED_URL, providerId: 'youtube' });
        await waitForPromises();
      });

      it('inserts an iframe node with the URL that was resolved', () => {
        expect(iframeNodes()[0].attrs).toMatchObject({
          src: YOUTUBE_EMBED_URL,
          canonicalSrc: YOUTUBE_URL,
          providerId: 'youtube',
        });
      });
    });

    describe('when cancelled', () => {
      beforeEach(async () => {
        await wrapper.findByTestId('cancel-iframe-insert').trigger('click');
      });

      it('closes the insert', () => {
        expect(insertRange()).toBeNull();
      });
    });

    describe('when the menu hides', () => {
      beforeEach(async () => {
        contentEditor.resolveEmbed.mockResolvedValue(null);
        await submit({ src: 'https://evil.example.com/embed/xyz', alt: 'A video' });

        await findBubbleMenu().vm.$emit('hidden');
      });

      it('closes the insert', () => {
        expect(insertRange()).toBeNull();
      });

      it('clears the form', () => {
        expect(findSrcInput().element.value).toBe('');
        expect(findAltInput().element.value).toBe('');
        expect(findInvalidFeedback().exists()).toBe(false);
      });
    });
  });
});
