import { Node, mergeAttributes } from '@tiptap/core';
import { PARSE_HTML_PRIORITY_HIGHEST } from '../constants';
import { decodeFootnoteName } from '../services/utils';

// Read the href, not the id: the second reference to [^1] has the id
// fnref-1-2-<suffix>, while every reference links to #fn-1-<suffix>. The
// greedy name leaves only the last -<digits>, the suffix, outside it.
const extractFootnoteIdentifier = (element) =>
  decodeFootnoteName(/^#fn-(.+)-\d+$/.exec(element.querySelector('a')?.getAttribute('href'))?.[1]);

export default Node.create({
  name: 'footnoteReference',

  inline: true,

  group: 'inline',

  atom: true,

  draggable: true,

  selectable: true,

  addOptions() {
    return {
      HTMLAttributes: {
        dir: 'auto',
      },
    };
  },

  addAttributes() {
    return {
      identifier: {
        default: null,
        parseHTML: extractFootnoteIdentifier,
      },
      label: {
        default: null,
        parseHTML: extractFootnoteIdentifier,
      },
    };
  },

  parseHTML() {
    return [{ tag: 'sup.footnote-ref', priority: PARSE_HTML_PRIORITY_HIGHEST }];
  },

  renderHTML({ HTMLAttributes: { label, ...HTMLAttributes } }) {
    return ['sup', mergeAttributes(this.options.HTMLAttributes, HTMLAttributes), label];
  },
});
