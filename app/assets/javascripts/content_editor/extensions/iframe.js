import { Node } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { VueNodeViewRenderer } from '@tiptap/vue-2';
import { enabledIframeProviderNames, isIframeSrcAllowed } from '~/behaviors/markdown/render_iframe';
import { s__, sprintf, createListFormat } from '~/locale';
import { PARSE_HTML_PRIORITY_HIGHEST } from '../constants';
import IframeWrapper from '../components/wrappers/iframe.vue';

export const iframeInsertPluginKey = new PluginKey('iframeInsert');

export const embedNotAllowedMessage = () =>
  sprintf(s__('ContentEditor|Enter a URL from an allowed embed provider: %{providers}.'), {
    providers: createListFormat({ type: 'disjunction' }).format(enabledIframeProviderNames()),
  });

export default Node.create({
  name: 'iframe',
  group: 'inline',
  inline: true,
  draggable: true,

  addAttributes() {
    return {
      src: {
        default: null,
        parseHTML: (element) => element.dataset.iframeSrc,
      },
      canonicalSrc: {
        default: null,
        parseHTML: (element) => element.dataset.iframeCanonicalSrc,
      },
      providerId: {
        default: null,
        parseHTML: (element) => element.dataset.iframeProviderId,
      },
      alt: {
        default: null,
        parseHTML: (element) => element.dataset.title,
      },
      width: {
        default: null,
        parseHTML: (element) => element.dataset.width,
      },
      height: {
        default: null,
        parseHTML: (element) => element.dataset.height,
      },
    };
  },

  parseHTML() {
    return [
      {
        priority: PARSE_HTML_PRIORITY_HIGHEST,
        tag: 'span.js-render-iframe',
        getAttrs: (element) =>
          isIframeSrcAllowed(element.dataset.iframeSrc, element.dataset.iframeProviderId)
            ? null
            : false,
      },
    ];
  },

  renderHTML({ node }) {
    const { src, canonicalSrc, providerId, alt, width, height } = node.attrs;

    return [
      'span',
      {
        class: 'media-container iframe-container js-render-iframe',
        'data-iframe-src': src,
        'data-iframe-canonical-src': canonicalSrc,
        'data-iframe-provider-id': providerId,
        'data-title': alt,
        'data-width': width,
        'data-height': height,
      },
      ['a', { href: canonicalSrc }, alt || canonicalSrc],
    ];
  },

  addNodeView() {
    return VueNodeViewRenderer(IframeWrapper);
  },

  addCommands() {
    return {
      insertIframe:
        () =>
        ({ tr, commands }) =>
          commands.setMeta(iframeInsertPluginKey, {
            from: tr.selection.from,
            to: tr.selection.to,
          }),
    };
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: iframeInsertPluginKey,
        state: {
          init: () => null,
          apply(tr, range) {
            const meta = tr.getMeta(iframeInsertPluginKey);
            if (meta !== undefined) return meta;
            if (!range) return null;

            const from = tr.mapping.map(range.from);
            const to = tr.mapping.map(range.to);
            const { selection } = tr;

            return selection.from === from && selection.to === to ? { from, to } : null;
          },
        },
      }),
    ];
  },
});
