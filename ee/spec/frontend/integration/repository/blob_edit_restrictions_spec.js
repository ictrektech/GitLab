import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { getBlobControls } from 'ee_jest/integration/repository/fixture_variants';
import {
  mountBlobHeaderArea,
  mountHeaderArea,
  findEditDropdownToggle,
  findSingleFileEditorItem,
  findWebIdeEditItem,
  findBlobOverflowMenuToggle,
  findPermalinkItem,
  findReplaceItem,
  findDeleteItem,
  DEFAULT_BRANCH,
} from './test_setup';

describe('Blob controls in an archived project', () => {
  beforeEach(async () => {
    setQueryVariant(getBlobControls).archived();
    await mountBlobHeaderArea();
  });

  it('disables Edit and offers no Replace or Delete', async () => {
    // The toggle renders enabled while blob controls load, so wait for the
    // archived state to land rather than for the toggle to exist. GlButton
    // disables via aria-disabled to stay focusable.
    await waitForAssertion(() => {
      expect(findEditDropdownToggle().getAttribute('aria-disabled')).toBe('true');
    });

    await waitAndClick(findBlobOverflowMenuToggle);

    // The permalink item proves the menu content rendered, so absence is meaningful.
    await waitForElement(findPermalinkItem);
    expect(findReplaceItem()).toBe(null);
    expect(findDeleteItem()).toBe(null);
  });
});

describe('Blob controls for a binary file', () => {
  beforeEach(async () => {
    await mountHeaderArea({ route: `/-/blob/${DEFAULT_BRANCH}/files/images/logo-black.png` });
  });

  it('offers the Web IDE but not the single file editor', async () => {
    await waitForElement(findBlobOverflowMenuToggle);
    await waitAndClick(findEditDropdownToggle);

    await waitForElement(findWebIdeEditItem);
    expect(findSingleFileEditorItem()).toBe(null);
  });
});
