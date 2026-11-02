import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
} from 'ee_jest/integration/helpers/test_helpers';
import { getBlobControls } from 'ee_jest/integration/repository/fixture_variants';
import {
  mountBlobHeaderArea,
  findEditDropdownToggle,
  findSingleFileEditorItem,
  findWebIdeEditItem,
  findBlobOverflowMenuToggle,
  findReplaceItem,
  findDeleteItem,
  findForkSuggestionMessage,
  findForkSuggestionForkButton,
  findForkSuggestionCancelButton,
} from './test_setup';

const NON_WRITABLE_BLOB = getBlobControls.NON_WRITABLE.data.project.repository.blobs.nodes[0];
const BASE_BLOB = getBlobControls.BASE.data.project.repository.blobs.nodes[0];

// The modal offers a fork because forking is a POST to forkAndViewPath; the
// fork itself and the later commit into it stay covered by Capybara
// ("commits an edited file in a forked project" in user_edits_files_spec.rb).
// Replace and Delete stay disabled until the project permissions land, and a
// disabled button swallows the click, so wait for the enabled state.
const clickWhenEnabled = async (finder) => {
  await waitForAssertion(() => {
    expect(finder().disabled).toBe(false);
  });
  finder().click();
};

const expectForkSuggestionModal = async () => {
  const message = await waitForElement(findForkSuggestionMessage);

  expect(getText(message)).toBe(
    "You're not allowed to make changes to this project directly. Create a fork to make changes and submit a merge request.",
  );

  const forkButton = findForkSuggestionForkButton();
  expect(forkButton.getAttribute('href')).toBe(NON_WRITABLE_BLOB.forkAndViewPath);
  expect(forkButton.dataset.method).toBe('post');
};

describe('Fork suggestion for a user who cannot push', () => {
  beforeEach(async () => {
    setQueryVariant(getBlobControls).nonWritable();
    await mountBlobHeaderArea();
  });

  it('suggests forking when editing in the single file editor', async () => {
    await waitAndClick(findEditDropdownToggle);
    await waitAndClick(findSingleFileEditorItem);

    await expectForkSuggestionModal();

    findForkSuggestionCancelButton().click();
    await waitForElementToBeNull(findForkSuggestionMessage);
  });

  it('suggests forking when opening the Web IDE', async () => {
    await waitAndClick(findEditDropdownToggle);
    // The Web IDE item renders while blob controls still load, when the fork
    // flags are not known yet; the single file item only renders once they
    // landed, so its presence means the Web IDE item routes correctly too.
    await waitForElement(findSingleFileEditorItem);
    await waitAndClick(findWebIdeEditItem);

    await expectForkSuggestionModal();
  });

  it('suggests forking when replacing the file', async () => {
    await waitAndClick(findBlobOverflowMenuToggle);
    await clickWhenEnabled(findReplaceItem);

    await expectForkSuggestionModal();
  });

  it('suggests forking when deleting the file', async () => {
    await waitAndClick(findBlobOverflowMenuToggle);
    await clickWhenEnabled(findDeleteItem);

    await expectForkSuggestionModal();
  });
});

describe('Single file editor when the user can modify the blob', () => {
  it('links straight to the edit page without a fork suggestion', async () => {
    await mountBlobHeaderArea();
    await waitAndClick(findEditDropdownToggle);

    const item = await waitForElement(findSingleFileEditorItem);

    expect(item.getAttribute('href')).toBe(BASE_BLOB.editBlobPath);
    expect(findForkSuggestionMessage()).toBe(null);
  });
});
