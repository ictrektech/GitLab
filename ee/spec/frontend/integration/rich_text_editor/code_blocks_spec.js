import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  getText,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findCodeBlockBubbleMenu,
  findContentEditor,
  findMarkdownTextarea,
  pressKey,
  setPlainTextContent,
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

describe('Rich text editor - code blocks', () => {
  useWorkItemCreateHost();

  const findCodeBlock = () => findContentEditor().querySelector('pre');
  const findLanguageToggle = () =>
    findCodeBlockBubbleMenu()?.querySelector('[data-testid="base-dropdown-toggle"]') ?? null;

  describe('when a code block is typed with a language', () => {
    beforeEach(async () => {
      await switchToRichText();
      await waitForFocus(findContentEditor);

      pressKey('Enter');
      pressKey('Enter');
    });

    describe('when the language is js', () => {
      beforeEach(async () => {
        typeInContentEditor('```js ');
        typeInContentEditor('var a = 0');

        await waitForElement(findCodeBlock);
      });

      it('applies the syntax highlighting theme classes', () => {
        expect([...findCodeBlock().classList]).toEqual(
          expect.arrayContaining(['code', 'highlight', 'code-syntax-highlight-theme']),
        );
      });

      it('shows the language as Javascript in the bubble menu', async () => {
        await waitForAssertion(() => {
          expect(getText(findLanguageToggle())).toBe('Javascript');
        });
      });
    });

    describe('when the language is nomnoml', () => {
      beforeEach(() => {
        typeInContentEditor('```nomnoml ');
        typeInContentEditor('test');
      });

      it('shows the language as a custom type in the bubble menu', async () => {
        await waitForAssertion(() => {
          expect(getText(findLanguageToggle())).toBe('Custom (nomnoml)');
        });
      });
    });
  });

  describe('when the plain text editor has a code block with lines starting with a slash', () => {
    const markdown =
      '```\nvar test1 10\n// testing comment\n/usr/bin/env bash\ntest 1\n```\n\nNotes';

    beforeEach(async () => {
      await setPlainTextContent(markdown);
      await switchToRichText();
      await waitForFocus(findContentEditor);
      await waitForAssertion(() => {
        expect(getText(findCodeBlock())).toContain('// testing comment');
      });

      typeInContentEditor(' edited');
      await waitForSerializedMarkdown(markdown.replace('Notes', 'Notes edited'));

      await switchToPlainText();
    });

    it('keeps the lines intact after switching back', () => {
      expect(findMarkdownTextarea().value).toBe(markdown.replace('Notes', 'Notes edited'));
    });
  });
});
