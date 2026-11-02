import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  findButtonByText,
  getText,
  screen,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { reloadWorkItemCreatePage } from 'ee_jest/integration/work_items/test_setup';
import {
  findContentEditor,
  findContentEditorAlert,
  findFormattingToolbar,
  findMarkdownField,
  findMarkdownTextarea,
  findSerializedMarkdown,
  insertTableFromToolbar,
  pressKey,
  setPlainTextContent,
  stubUnsupportedExecCommand,
  switchToPlainText,
  switchToRichText,
  typeInContentEditor,
  useWorkItemCreateHost,
  waitForFocus,
  waitForPendingRequests,
  waitForSerializedMarkdown,
} from 'ee_jest/integration/rich_text_editor/test_setup';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

Vue.use(VueApollo);

describe('Rich text editor - common', () => {
  useWorkItemCreateHost();
  stubUnsupportedExecCommand();

  const findPlaceholderAnnouncement = () =>
    screen.queryByTestId('content-editor-placeholder-announcement');
  const findPlaceholders = () => [
    ...findContentEditor().querySelectorAll('[data-testid="content-editor-placeholder"]'),
  ];
  const findLink = (name) => {
    const editor = findContentEditor();
    return editor ? within(editor).queryByRole('link', { name }) : null;
  };

  describe('when switching to rich text', () => {
    beforeEach(async () => {
      await switchToRichText();
    });

    it('focuses the rich text editor', async () => {
      await waitForFocus(findContentEditor);
    });

    describe('when switching back to plain text', () => {
      beforeEach(async () => {
        await switchToPlainText();
      });

      it('focuses the plain text editor', async () => {
        await waitForFocus(findMarkdownTextarea);
      });
    });

    describe('when a paragraph and a list are typed', () => {
      beforeEach(async () => {
        await waitForFocus(findContentEditor);

        typeInContentEditor('hello world');
        pressKey('Enter');
        typeInContentEditor('* list item 1');
        pressKey('Enter');
        typeInContentEditor('list item 2');
        await waitForSerializedMarkdown('hello world\n\n* list item 1\n* list item 2');

        await switchToPlainText();
      });

      it('serializes them to markdown', () => {
        expect(findMarkdownTextarea().value).toBe('hello world\n\n* list item 1\n* list item 2');
      });
    });

    describe('when the editor is remounted with typed content', () => {
      beforeEach(async () => {
        await waitForFocus(findContentEditor);

        typeInContentEditor('Undo keeps this text');
        await waitForSerializedMarkdown('Undo keeps this text');

        await switchToPlainText();
        await switchToRichText();

        await waitForAssertion(() => {
          expect(getText(findContentEditor())).toBe('Undo keeps this text');
        });
        await waitForFocus(findContentEditor);
      });

      describe('when undo is pressed', () => {
        beforeEach(() => {
          pressKey('z', { ctrlKey: true });
        });

        it('keeps the reloaded document', () => {
          expect(getText(findContentEditor())).toBe('Undo keeps this text');
        });
      });

      describe('when more text is typed and undo is pressed', () => {
        beforeEach(async () => {
          typeInContentEditor(' plus more');
          await waitForSerializedMarkdown('Undo keeps this text plus more');

          pressKey('z', { ctrlKey: true });
        });

        it('reverts only the newly typed text', async () => {
          await waitForSerializedMarkdown('Undo keeps this text');

          expect(getText(findContentEditor())).toBe('Undo keeps this text');
        });
      });
    });

    describe('when a table is inserted from the toolbar and its header typed', () => {
      const findCellMenuItem = (name) => {
        const editor = screen.queryByTestId('content-editor');
        return editor ? findButtonByText(name, editor) : null;
      };
      const clickCellMenuItem = (name) =>
        waitForAssertion(() => {
          const item = findCellMenuItem(name);
          expect(item).not.toBeNull();
          item.click();
        });

      beforeEach(async () => {
        await waitForFocus(findContentEditor);
        await insertTableFromToolbar(findFormattingToolbar, 2, 2);
        await waitForFocus(findContentEditor);

        typeInContentEditor('Item');
        pressKey('Tab');
        typeInContentEditor('Quantity');
      });

      describe('when the column is aligned from the cell menu', () => {
        beforeEach(async () => {
          await clickCellMenuItem(/Select action$/);
          await clickCellMenuItem('Align column center');
        });

        it('aligns every cell in the column', async () => {
          await waitForAssertion(() => {
            expect(findContentEditor().querySelectorAll('th[align="center"]')).toHaveLength(1);
            expect(findContentEditor().querySelectorAll('td[align="center"]')).toHaveLength(1);
          });
        });

        describe('when typing continues', () => {
          beforeEach(async () => {
            await waitForFocus(findContentEditor);

            typeInContentEditor(' (kg)');
          });

          it('types into the same cell', async () => {
            await waitForAssertion(() => {
              expect(findSerializedMarkdown().value).toMatch(
                /\| Item \| Quantity \(kg\) \|\n\|-+\|:-+:\|/,
              );
            });
          });
        });
      });
    });

    describe('when content is typed and the page is reloaded', () => {
      beforeEach(async () => {
        await waitForFocus(findContentEditor);

        typeInContentEditor('Typing text in the content editor');
        await waitForSerializedMarkdown('Typing text in the content editor');

        await reloadWorkItemCreatePage();
      });

      it('restores the draft in the rich text editor', async () => {
        await waitForAssertion(() => {
          expect(getText(findContentEditor())).toBe('Typing text in the content editor');
        });
      });
    });

    describe('when a reference is typed on a new line', () => {
      beforeEach(async () => {
        await waitForFocus(findContentEditor);

        pressKey('Enter');
      });

      describe('when the username exists', () => {
        beforeEach(() => {
          typeInContentEditor('@abc123 some text');
        });

        it('links the user reference', async () => {
          await waitForAssertion(() => {
            expect(findLink('@abc123')?.getAttribute('href')).toBe('/abc123');
          });
        });
      });

      describe('when the username does not exist', () => {
        beforeEach(async () => {
          typeInContentEditor('@nonexistentuser some text');

          await waitForAssertion(() => {
            expect(lastRequestVariables('previewMarkdown')).toEqual({
              text: '@nonexistentuser @nonexistentuser+ @nonexistentuser+s',
            });
          });
          await waitForPendingRequests();
        });

        it('does not link the reference', () => {
          expect(findLink('@nonexistentuser')).toBe(null);
        });
      });

      describe('when the username is in inline code', () => {
        beforeEach(async () => {
          typeInContentEditor('`@abc123` some text');

          await waitForSerializedMarkdown('\n`@abc123` some text');
        });

        it('does not link the reference', () => {
          expect(findContentEditor().querySelector('code').textContent).toBe('@abc123');
          expect(findLink('@abc123')).toBe(null);
        });
      });
    });
  });

  describe('when the plain text editor has content', () => {
    describe('with a placeholder', () => {
      beforeEach(async () => {
        await setPlainTextContent('Server: %{gitlab_server}');
        await switchToRichText();
        await waitForFocus(findContentEditor);
        await waitForElement(findPlaceholderAnnouncement);
      });

      describe('when the placeholder is reselected with the keyboard', () => {
        beforeEach(() => {
          pressKey('ArrowLeft');
        });

        it('announces the value and the placeholder syntax', async () => {
          await waitForAssertion(() => {
            expect(findPlaceholderAnnouncement().textContent).toBe(
              'gitlab.example.com, placeholder %{gitlab_server}',
            );
          });
        });

        describe('when the cursor moves past it', () => {
          beforeEach(async () => {
            await waitForAssertion(() => {
              expect(findPlaceholderAnnouncement().textContent).not.toBe('');
            });

            pressKey('ArrowRight');
          });

          it('clears the announcement', async () => {
            await waitForAssertion(() => {
              expect(findPlaceholderAnnouncement().textContent).toBe('');
            });
          });
        });
      });

      describe('when text is typed after the placeholder', () => {
        beforeEach(async () => {
          typeInContentEditor(' hello world');
          await waitForSerializedMarkdown('Server: %{gitlab_server} hello world');

          await switchToPlainText();
        });

        it('preserves the placeholder syntax', () => {
          expect(findMarkdownTextarea().value).toBe('Server: %{gitlab_server} hello world');
        });
      });

      describe('when another placeholder is typed', () => {
        beforeEach(() => {
          typeInContentEditor(' and %{gitlab_server} again');
        });

        it('resolves it to its value', async () => {
          await waitForAssertion(() => {
            expect(findPlaceholders().map((placeholder) => placeholder.firstChild.data)).toEqual([
              'gitlab.example.com',
              'gitlab.example.com',
            ]);
          });
        });

        describe('when switching back to plain text', () => {
          beforeEach(async () => {
            await waitForAssertion(() => {
              expect(findPlaceholders()).toHaveLength(2);
            });
            await waitForSerializedMarkdown('Server: %{gitlab_server} and %{gitlab_server} again');

            await switchToPlainText();
          });

          it('keeps both placeholders as syntax', () => {
            expect(findMarkdownTextarea().value).toBe(
              'Server: %{gitlab_server} and %{gitlab_server} again',
            );
          });
        });
      });
    });

    describe('with dollar-sign math', () => {
      const findMath = () => findContentEditor().querySelector('code');

      beforeEach(async () => {
        await setPlainTextContent('The energy is $E = mc^2$ here');
        await switchToRichText();
        await waitForFocus(findContentEditor);
      });

      it('renders the math', async () => {
        await waitForAssertion(() => {
          expect(getText(findMath())).toBe('E = mc^2');
        });
      });

      describe('when text is typed after it and switching back to plain text', () => {
        beforeEach(async () => {
          await waitForElement(findMath);

          typeInContentEditor(' again');
          await waitForSerializedMarkdown('The energy is $E = mc^2$ here again');

          await switchToPlainText();
        });

        it('keeps the dollar-sign syntax', () => {
          expect(findMarkdownTextarea().value).toBe('The energy is $E = mc^2$ here again');
        });
      });
    });

    describe('with a table followed by a paragraph', () => {
      beforeEach(async () => {
        await setPlainTextContent(
          '| First Header | Second Header |\n|--------------|---------------|\n| Content from cell 1 | Content from cell 2 |\n\nContent below table',
        );
        await switchToRichText();
      });

      it('renders the table without an error', async () => {
        await waitForAssertion(() => {
          expect(getText(findContentEditor().querySelector('td'))).toBe('Content from cell 1');
        });

        expect(getText(findContentEditor())).toContain('Content below table');
        expect(findContentEditorAlert()).toBe(null);
      });
    });

    describe('with a nested checklist', () => {
      beforeEach(async () => {
        await setPlainTextContent(
          '- [ ] checklist\n  - [ ] nested checklist\n  - [ ] nested checklist 2',
        );
        await switchToRichText();

        const checkbox = await waitForElement(() =>
          findContentEditor().querySelector('[aria-label="Check option: nested checklist"]'),
        );
        checkbox.click();
        await waitForSerializedMarkdown(
          '- [ ] checklist\n  - [x] nested checklist\n  - [ ] nested checklist 2',
        );

        await switchToPlainText();
      });

      it('serializes the checked item', () => {
        expect(findMarkdownTextarea().value).toBe(
          '- [ ] checklist\n  - [x] nested checklist\n  - [ ] nested checklist 2',
        );
      });
    });

    describe('with a table inserted from the toolbar', () => {
      beforeEach(async () => {
        await insertTableFromToolbar(findMarkdownField, 2, 2);
        await switchToRichText();
        await waitForFocus(findContentEditor);
        await waitForAssertion(() => {
          expect(getText(findContentEditor().querySelector('th'))).toBe('header');
        });
      });

      describe('when a list is typed into a cell', () => {
        beforeEach(() => {
          typeInContentEditor('* list item');
        });

        it('warns that the table will be converted to HTML', async () => {
          await waitForAssertion(() => {
            expect(getText(findContentEditorAlert())).toBe(
              'Tables containing block elements (like multiple paragraphs, lists or blockquotes, or task lists with text or multiple items) are not supported in Markdown and will be converted to HTML.',
            );
          });
        });

        describe('when switching back to plain text', () => {
          beforeEach(async () => {
            await waitForAssertion(() => {
              expect(findSerializedMarkdown().value).toContain('* list item');
            });

            await switchToPlainText();
          });

          it('serializes the table as HTML', () => {
            expect(findMarkdownTextarea().value).toBe(
              '<table>\n<tr>\n<th>header</th>\n<th>header</th>\n</tr>\n<tr>\n<td></td>\n<td></td>\n</tr>\n<tr>\n<td></td>\n<td>\n\n* list item\n</td>\n</tr>\n</table>\n\n',
            );
          });
        });
      });
    });
  });
});
