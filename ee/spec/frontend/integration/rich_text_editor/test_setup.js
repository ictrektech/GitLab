import { ignoreConsoleMessages } from 'helpers/console_watcher';
import { initEmojiMock, clearEmojiMock } from 'helpers/emoji';
import waitForPromises from 'helpers/wait_for_promises';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  findButtonByText,
  screen,
  setInputValue,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { setFeatureFlags } from 'ee_jest/integration/helpers/setup_utils';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { mountWorkItemCreatePage } from 'ee_jest/integration/work_items/test_setup';
import { installRichTextEditorHandlers } from 'ee_jest/integration/rich_text_editor/handlers';

export const ignoreTiptapWarnings = () =>
  ignoreConsoleMessages([
    /^\[Vue warn\]: Avoid mutating a prop directly[\s\S]*Prop being mutated: "(node|decorations|innerDecorations|selected)"/,
    /^%ctippy\.js[\s\S]*(?:(?:hide|show|setProps)\(\) was called on a |destroy\(\) was called on an already-)destroyed instance/,
  ]);

export const useWorkItemCreateHost = () => {
  ignoreTiptapWarnings();

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    installRichTextEditorHandlers();
    setFeatureFlags({ markdownPlaceholders: true });
    await initEmojiMock();
    await apolloProvider.defaultClient.cache.reset();
    await mountWorkItemCreatePage();
  });

  afterEach(() => {
    clearEmojiMock();
  });
};

export const stubUnsupportedExecCommand = () => {
  beforeEach(() => {
    document.execCommand = () => false;
  });

  afterEach(() => {
    delete document.execCommand;
  });
};

export const findModeSwitcher = () => screen.queryByTestId('editing-mode-switcher');

export const findContentEditor = () =>
  screen.queryByTestId('content-editor')?.querySelector('.ProseMirror[contenteditable]') ?? null;

export const findMarkdownField = () => screen.queryByTestId('markdown-field');

export const findFormattingToolbar = () => screen.queryByTestId('formatting-toolbar');

export const findMarkdownTextarea = () => findMarkdownField()?.querySelector('textarea') ?? null;

export const findContentEditorAlert = () => {
  const container = screen.queryByTestId('content-editor')?.closest('.md-area');
  return container ? within(container).queryByRole('alert') : null;
};

export const findToolbarButton = (testId) =>
  screen.queryByTestId('formatting-toolbar')?.querySelector(`[data-testid="${testId}"]`) ?? null;

export const findLinkBubbleMenu = () => screen.queryByTestId('link-bubble-menu');

export const findCodeBlockBubbleMenu = () => screen.queryByTestId('code-block-bubble-menu');

export const findSerializedMarkdown = () =>
  document.querySelector('.md-content-editor-wrapper > input[type="hidden"]');

export const switchToRichText = async () => {
  await waitAndClick(findModeSwitcher);
  return waitForElement(findContentEditor);
};

export const switchToPlainText = async () => {
  await waitAndClick(findModeSwitcher);
  return waitForElement(findMarkdownTextarea);
};

export const attachFile = (file) => {
  const input = screen.queryByTestId('file-upload-field');
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  input.dispatchEvent(new Event('change', { bubbles: true }));
};

export const setPlainTextContent = async (markdown) => {
  setInputValue(await waitForElement(findMarkdownTextarea), markdown);
};

export const waitForFocus = (finder) =>
  waitForAssertion(() => {
    expect(document.activeElement).toBe(finder());
  });

export const insertTableFromToolbar = async (findToolbar, rows, cols) => {
  const toolbar = await waitForElement(findToolbar);
  findButtonByText(/Insert table$/, toolbar).click();
  await waitForFocus(() => findButtonByText('Insert a 1×1 table', toolbar));

  const cell = findButtonByText(`Insert a ${rows}×${cols} table`, toolbar);
  cell.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
  cell.click();
};

export const waitForPendingRequests = async () => {
  await waitForAssertion(() => {
    expect(window.pendingRequests).toBe(0);
  });
  await waitForPromises();
};

const insertAtSelection = (character) => {
  const selection = document.getSelection();
  let { anchorNode: node, anchorOffset: offset } = selection;

  if (node.nodeType !== Node.TEXT_NODE) {
    const textNode = document.createTextNode('');
    const next = node.childNodes[offset] ?? null;

    if (next?.nodeName === 'BR') {
      next.replaceWith(textNode);
    } else {
      node.insertBefore(textNode, next);
    }

    node = textNode;
    offset = 0;
  }

  node.insertData(offset, character);
  selection.collapse(node, offset + character.length);
  document.dispatchEvent(new Event('selectionchange'));
};

const findTextPosition = (index) => {
  const walker = document.createTreeWalker(findContentEditor(), NodeFilter.SHOW_TEXT);
  let remaining = index;

  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (remaining <= node.data.length) return { node, offset: remaining };
    remaining -= node.data.length;
  }

  throw new Error(`Offset ${index} is past the end of the rich text editor`);
};

const setSelection = (text, { collapseToEnd }) => {
  expect(document.activeElement).toBe(findContentEditor());

  const start = findContentEditor().textContent.indexOf(text);
  expect(start).not.toBe(-1);

  const end = findTextPosition(start + text.length);
  const anchor = collapseToEnd ? end : findTextPosition(start);

  document.getSelection().setBaseAndExtent(anchor.node, anchor.offset, end.node, end.offset);
  document.dispatchEvent(new Event('selectionchange'));
};

export const selectText = (text) => setSelection(text, { collapseToEnd: false });

export const placeCursorAfter = (text) => setSelection(text, { collapseToEnd: true });

export const typeInContentEditor = (text) => {
  expect(document.activeElement).toBe(findContentEditor());

  [...text].forEach(insertAtSelection);
};

// The set of `keyCode`s actually needed by the frontend. Anything not listed here is handled by its `key` instead.
const KEY_CODES = { ArrowLeft: 37, ArrowRight: 39 };

export const pressKey = (key, modifiers = {}) => {
  document.activeElement.dispatchEvent(
    new KeyboardEvent('keydown', {
      key,
      keyCode: KEY_CODES[key],
      bubbles: true,
      cancelable: true,
      ...modifiers,
    }),
  );
};

const dispatchClipboardEvent = (type, clipboardData) => {
  findContentEditor().dispatchEvent(new ClipboardEvent(type, { clipboardData, cancelable: true }));
  return clipboardData;
};

export const cutSelection = () => dispatchClipboardEvent('cut', new DataTransfer());

export const copySelection = () => dispatchClipboardEvent('copy', new DataTransfer());

export const pasteClipboard = (clipboardData) => {
  pressKey('v', { ctrlKey: true });
  dispatchClipboardEvent('paste', clipboardData);
};

export const pasteClipboardAsPlainText = (clipboardData) => {
  const plainText = new DataTransfer();
  plainText.setData('text/plain', clipboardData.getData('text/plain'));

  pressKey('V', { ctrlKey: true, shiftKey: true });
  dispatchClipboardEvent('paste', plainText);
};

export const waitForSerializedMarkdown = (markdown) =>
  waitForAssertion(() => {
    expect(findSerializedMarkdown().value).toBe(markdown);
  });
