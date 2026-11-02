import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { getText, waitForAssertion } from 'ee_jest/integration/helpers/test_helpers';
import {
  copySelection,
  cutSelection,
  findContentEditor,
  findMarkdownTextarea,
  findSerializedMarkdown,
  pasteClipboard,
  pasteClipboardAsPlainText,
  placeCursorAfter,
  pressKey,
  selectText,
  switchToPlainText,
  switchToRichText,
  typeInContentEditor,
  useWorkItemCreateHost,
  waitForFocus,
  waitForSerializedMarkdown,
} from 'ee_jest/integration/rich_text_editor/test_setup';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

Vue.use(VueApollo);

describe('Rich text editor - copy/paste', () => {
  useWorkItemCreateHost();

  const findInEditor = (selector) => findContentEditor().querySelector(selector);
  const findLoader = () => findInEditor('.gl-dots-loader');
  const findCodeBlock = () => findInEditor('pre code');

  const selectAll = () => pressKey('a', { ctrlKey: true });

  const waitForSerializedMarkdownMatching = (pattern) =>
    waitForAssertion(() => {
      expect(findSerializedMarkdown().value).toMatch(pattern);
    });

  beforeEach(async () => {
    await switchToRichText();
    await waitForFocus(findContentEditor);
  });

  describe('when formatted text has been cut', () => {
    let clipboard;

    beforeEach(() => {
      typeInContentEditor('Some **rich** _text_ ~~content~~ [link](https://gitlab.com)');
      selectAll();
      clipboard = cutSelection();
    });

    describe('when it is pasted', () => {
      beforeEach(() => {
        pasteClipboard(clipboard);
      });

      it('keeps the formatting', async () => {
        await waitForAssertion(() => {
          expect(getText(findInEditor('strong'))).toBe('rich');
          expect(getText(findInEditor('em'))).toBe('text');
          expect(getText(findInEditor('s'))).toBe('content');
          expect(getText(findInEditor('a[href="https://gitlab.com"]'))).toBe('link');
        });
      });

      describe('when the paste is undone', () => {
        beforeEach(async () => {
          await waitForAssertion(() => {
            expect(findInEditor('strong')).not.toBeNull();
          });

          pressKey('z', { ctrlKey: true });
        });

        it('does not show a loading indicator', () => {
          expect(findLoader()).toBeNull();
        });
      });
    });

    describe('when it is pasted over a select-all selection', () => {
      beforeEach(() => {
        typeInContentEditor('Text to replace');
        selectAll();
        pasteClipboard(clipboard);
      });

      it('replaces the entire content', async () => {
        await waitForAssertion(() => {
          expect(getText(findInEditor('strong'))).toBe('rich');
        });

        expect(findContentEditor().textContent).not.toContain('Text to replace');
        expect(findLoader()).toBeNull();
      });
    });

    describe('when it is pasted as plain text', () => {
      beforeEach(() => {
        pasteClipboardAsPlainText(clipboard);
      });

      it('drops the formatting', async () => {
        await waitForAssertion(() => {
          expect(getText(findContentEditor())).toBe('Some rich text content link');
        });

        expect(findContentEditor().querySelectorAll('strong, em, s, a')).toHaveLength(0);
      });
    });

    describe('when it is pasted inside a markdown code block', () => {
      beforeEach(() => {
        typeInContentEditor('```md ');
        pasteClipboard(clipboard);
      });

      it('pastes the raw markdown', async () => {
        await waitForAssertion(() => {
          expect(getText(findCodeBlock())).toBe(
            'Some **rich** _text_ ~~content~~ [link](https://gitlab.com)',
          );
        });
      });
    });

    describe('when it is pasted inside a plaintext code block', () => {
      beforeEach(() => {
        typeInContentEditor('``` ');
        pasteClipboard(clipboard);
      });

      it('pastes the text without formatting', async () => {
        await waitForAssertion(() => {
          expect(getText(findCodeBlock())).toBe('Some rich text content link');
        });
      });
    });
  });

  describe('when indented lines have been cut', () => {
    let clipboard;

    beforeEach(() => {
      typeInContentEditor('    Some **rich**');
      pressKey('Enter');
      typeInContentEditor('    _text_');
      pressKey('Enter');
      typeInContentEditor('    ~~content~~');
      pressKey('Enter');
      typeInContentEditor('    [link](https://gitlab.com)');
      selectAll();
      clipboard = cutSelection();
    });

    describe('when they are pasted as plain text', () => {
      beforeEach(() => {
        pasteClipboardAsPlainText(clipboard);
      });

      it('strips the indentation', async () => {
        await waitForAssertion(() => {
          expect(getText(findContentEditor())).toBe('Some rich text content link');
        });

        expect(findContentEditor().textContent).not.toContain('    Some rich');
      });
    });
  });

  describe('when paragraphs are pasted as plain text into the middle of a paragraph', () => {
    beforeEach(() => {
      typeInContentEditor('before after');
      placeCursorAfter('before ');

      const clipboard = new DataTransfer();
      clipboard.setData('text/plain', 'first line\nsecond line\n\nthird paragraph');
      pasteClipboardAsPlainText(clipboard);
    });

    it('splits the paragraph around the pasted paragraphs', async () => {
      await waitForSerializedMarkdown('before first line\\\nsecond line\n\nthird paragraphafter');
    });
  });

  describe('when indented text has been cut', () => {
    let clipboard;

    beforeEach(() => {
      typeInContentEditor('  text with indentation');
      selectAll();
      clipboard = cutSelection();
    });

    describe('when it is pasted as plain text inside a plaintext code block', () => {
      beforeEach(() => {
        typeInContentEditor('``` ');
        pasteClipboardAsPlainText(clipboard);
      });

      it('keeps the indentation', async () => {
        await waitForAssertion(() => {
          expect(findCodeBlock().textContent).toBe('  text with indentation');
        });
      });
    });
  });

  describe('when text is copied from a list item', () => {
    let clipboard;

    beforeEach(() => {
      typeInContentEditor('* item one');
      selectText('one');
      clipboard = copySelection();
    });

    it('copies the selected text', () => {
      expect(document.getSelection().toString()).toBe('one');
    });

    describe('when it is pasted into the next list item', () => {
      beforeEach(async () => {
        placeCursorAfter('item one');
        pressKey('Enter');
        typeInContentEditor('item two');
        pasteClipboard(clipboard);

        await waitForSerializedMarkdownMatching(/item two.*one/s);
        await switchToPlainText();
      });

      it('inserts the text inline at the cursor', () => {
        expect(findMarkdownTextarea().value.trim()).toBe('* item one\n* item twoone');
      });
    });
  });

  describe('when text is copied from a paragraph', () => {
    let clipboard;

    beforeEach(() => {
      typeInContentEditor('plain one');
      selectText('one');
      clipboard = copySelection();
    });

    it('copies the selected text', () => {
      expect(document.getSelection().toString()).toBe('one');
    });

    describe('when it is pasted into a list item', () => {
      beforeEach(async () => {
        placeCursorAfter('plain one');
        pressKey('Enter');
        typeInContentEditor('* item one');
        pressKey('Enter');
        typeInContentEditor('item two');
        pasteClipboard(clipboard);

        await waitForSerializedMarkdownMatching(/item two.*one/s);
        await switchToPlainText();
      });

      it('inserts the text inline at the cursor', () => {
        expect(findMarkdownTextarea().value.trim()).toBe('plain one\n\n* item one\n* item twoone');
      });
    });
  });
});
