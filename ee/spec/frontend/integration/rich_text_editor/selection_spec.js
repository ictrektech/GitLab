import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  findButtonByText,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findContentEditor,
  pressKey,
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

describe('Rich text editor - selection', () => {
  useWorkItemCreateHost();

  const findSelectedTexts = () =>
    [...findContentEditor().querySelectorAll('.content-editor-selection')].map(
      (element) => element.textContent,
    );

  describe('when all text is selected and the editor loses focus', () => {
    beforeEach(async () => {
      await switchToRichText();
      await waitForFocus(findContentEditor);

      typeInContentEditor('The quick **brown** fox _jumps_ over the lazy dog!');
      pressKey('Enter');
      typeInContentEditor('[Link](https://gitlab.com)');
      pressKey('Enter');
      typeInContentEditor('Sphinx of black quartz, judge ~~my~~ vow!');
      pressKey('a', { ctrlKey: true });

      const moreOptions = findButtonByText(
        /More options$/,
        screen.queryByTestId('formatting-toolbar'),
      );
      moreOptions.focus();
      moreOptions.click();
    });

    it('keeps every selected text run highlighted', async () => {
      await waitForAssertion(() => {
        expect(findSelectedTexts()).toEqual([
          'The quick ',
          'brown',
          ' fox ',
          'jumps',
          ' over the lazy dog!',
          'Link',
          'Sphinx of black quartz, judge ',
          'my',
          ' vow!',
        ]);
      });
    });
  });
});
