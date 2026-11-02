import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  getText,
  setInputValue,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  attachFile,
  findContentEditor,
  findLinkBubbleMenu,
  findToolbarButton,
  placeCursorAfter,
  selectText,
  switchToRichText,
  typeInContentEditor,
  useWorkItemCreateHost,
  waitForFocus,
} from 'ee_jest/integration/rich_text_editor/test_setup';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn().mockReturnValue(true),
}));

Vue.use(VueApollo);

describe('Rich text editor - links', () => {
  useWorkItemCreateHost();

  const findLinkText = () => findLinkBubbleMenu()?.querySelector('#link-text') ?? null;
  const findLinkHref = () => findLinkBubbleMenu()?.querySelector('#link-href') ?? null;
  const findMenuButton = (testId) =>
    findLinkBubbleMenu()?.querySelector(`[data-testid="${testId}"]`) ?? null;
  const findApplyButton = () =>
    findLinkBubbleMenu()?.querySelector('button[type="submit"]') ?? null;
  const findLinks = () => [...findContentEditor().querySelectorAll('a')];
  const findLink = (href) => findContentEditor().querySelector(`a[href="${href}"]`);

  const fillInLink = ({ text, href }) => {
    if (text !== undefined) setInputValue(findLinkText(), text);
    setInputValue(findLinkHref(), href);
  };

  beforeEach(async () => {
    window.isSecureContext = true;

    await switchToRichText();
    await waitForFocus(findContentEditor);
  });

  afterEach(() => {
    delete window.isSecureContext;
  });

  describe('when the toolbar link button is clicked', () => {
    describe('with no text selected', () => {
      beforeEach(async () => {
        findToolbarButton('link').click();
        await waitForElement(findLinkHref);
      });

      it('opens an empty link form', () => {
        expect(findLinkText().value).toBe('');
        expect(findLinkHref().value).toBe('');
      });

      describe('when a link is entered and applied', () => {
        beforeEach(() => {
          fillInLink({ text: 'Link to GitLab home page', href: 'https://gitlab.com' });
          findApplyButton().click();
        });

        it('inserts the link', async () => {
          const link = await waitForElement(() => findLink('https://gitlab.com'));

          expect(getText(link)).toBe('Link to GitLab home page');
        });
      });

      describe('when a link is entered and cancelled', () => {
        beforeEach(async () => {
          fillInLink({ text: 'Link to GitLab home page', href: 'https://gitlab.com' });
          findMenuButton('cancel-link').click();

          await waitForElementToBeNull(findLinkHref);
        });

        it('does not insert a link', () => {
          expect(findLinks()).toHaveLength(0);
        });
      });
    });

    describe('with text selected', () => {
      beforeEach(async () => {
        typeInContentEditor('The quick brown fox jumps over the lazy dog');
        selectText('dog');
        findToolbarButton('link').click();
        await waitForElement(findLinkHref);
      });

      it('prefills the link text with the selection', () => {
        expect(findLinkText().value).toBe('dog');
        expect(findLinkHref().value).toBe('');
      });

      describe('when new text and a URL are applied', () => {
        beforeEach(() => {
          fillInLink({ text: 'new dog', href: 'https://en.wikipedia.org/wiki/Shiba_Inu' });
          findApplyButton().click();
        });

        it('links the new text', async () => {
          const link = await waitForElement(() =>
            findLink('https://en.wikipedia.org/wiki/Shiba_Inu'),
          );

          expect(getText(link)).toBe('new dog');
        });
      });
    });

    describe('with a selection spanning more than a link', () => {
      beforeEach(async () => {
        typeInContentEditor('a [b **c**](https://gitlab.com)');
        selectText('a b c');
        findToolbarButton('link').click();
        await waitForElement(findLinkHref);
      });

      it('prefills the link text with the whole selection', () => {
        expect(findLinkText().value).toBe('a b c');
        expect(findLinkHref().value).toBe('');
      });

      describe('when only the URL is applied', () => {
        beforeEach(() => {
          fillInLink({ href: 'https://about.gitlab.com' });
          findApplyButton().click();
        });

        it('expands the link over the selection and keeps its formatting', async () => {
          const link = await waitForElement(() => findLink('https://about.gitlab.com'));

          expect(getText(link)).toBe('a b c');
          expect(getText(link.querySelector('strong'))).toBe('c');
        });
      });

      describe('when new text and a URL are applied', () => {
        beforeEach(() => {
          fillInLink({ text: 'new text', href: 'https://about.gitlab.com' });
          findApplyButton().click();
        });

        it('replaces the selection with the new link', async () => {
          const link = await waitForElement(() => findLink('https://about.gitlab.com'));

          expect(getText(link)).toBe('new text');
          expect(findContentEditor().querySelector('strong')).toBe(null);
        });
      });
    });
  });

  describe('when the cursor is placed on an existing link', () => {
    beforeEach(async () => {
      typeInContentEditor('Link to [GitLab home **page**](https://gitlab.com)');
      placeCursorAfter('GitLab home pag');
      await waitForElement(() => findMenuButton('edit-link'));
    });

    describe('when edit is clicked', () => {
      beforeEach(async () => {
        findMenuButton('edit-link').click();
        await waitForElement(findLinkHref);
      });

      it('prefills the link form', () => {
        expect(findLinkText().value).toBe('GitLab home page');
        expect(findLinkHref().value).toBe('https://gitlab.com');
      });

      describe('when only the URL is changed and applied', () => {
        beforeEach(() => {
          fillInLink({ href: 'https://about.gitlab.com' });
          findApplyButton().click();
        });

        it('updates the URL and keeps the text and formatting', async () => {
          const link = await waitForElement(() => findLink('https://about.gitlab.com'));

          expect(getText(link)).toBe('GitLab home page');
          expect(getText(link.querySelector('strong'))).toBe('page');
        });
      });

      describe('when the text and URL are changed and applied', () => {
        beforeEach(() => {
          fillInLink({ text: 'GitLab about page', href: 'https://about.gitlab.com' });
          findApplyButton().click();
        });

        it('replaces the link text and URL', async () => {
          const link = await waitForElement(() => findLink('https://about.gitlab.com'));

          expect(getText(link)).toBe('GitLab about page');
          expect(findContentEditor().querySelector('strong')).toBe(null);
        });
      });

      describe('when cancel is clicked', () => {
        beforeEach(async () => {
          findMenuButton('cancel-link').click();
          await waitForElementToBeNull(findLinkHref);
        });

        it('leaves the link unchanged', () => {
          const link = findLink('https://gitlab.com');

          expect(getText(link)).toBe('GitLab home page');
          expect(getText(link.querySelector('strong'))).toBe('page');
        });
      });
    });

    describe('when unlink is clicked', () => {
      beforeEach(() => {
        findMenuButton('remove-link').click();
      });

      it('removes the link and keeps the formatting', async () => {
        await waitForAssertion(() => {
          expect(findLinks()).toHaveLength(0);
        });

        expect(getText(findContentEditor().querySelector('strong'))).toBe('page');
      });
    });

    describe('when copy is clicked', () => {
      beforeEach(() => {
        jest.spyOn(navigator.clipboard, 'writeText');
        findMenuButton('copy-link-url').click();
      });

      it('copies the external URL as written', () => {
        expect(navigator.clipboard.writeText).toHaveBeenCalledWith('https://gitlab.com');
      });
    });
  });

  describe('when a file is attached', () => {
    beforeEach(async () => {
      attachFile(new File(['%PDF-1.4'], 'sample.pdf', { type: 'application/pdf' }));

      await waitForAssertion(() => {
        expect(
          within(findContentEditor())
            .queryByRole('link', { name: 'sample.pdf' })
            ?.getAttribute('href'),
        ).toMatch(/^\/-\/project\/\d+\/uploads\/0123456789abcdef0123456789abcdef\/sample\.pdf$/);
      });

      placeCursorAfter('sample.pd');
      await waitForElement(() => findMenuButton('copy-link-url'));
    });

    describe('when copy is clicked', () => {
      beforeEach(() => {
        jest.spyOn(navigator.clipboard, 'writeText');
        findMenuButton('copy-link-url').click();
      });

      it('copies the full URL of the upload', () => {
        expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
          expect.stringMatching(
            /^http:\/\/test\.host\/-\/project\/\d+\/uploads\/0123456789abcdef0123456789abcdef\/sample\.pdf$/,
          ),
        );
      });
    });
  });
});
