import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getProjectInfo } from 'ee_jest/integration/repository/fixture_variants';
import {
  findToastMessages,
  getText,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
  waitForModalConfirm,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  mountHeaderArea,
  mountTreeHeaderArea,
  findLockButton,
  findLockDisclosureToggle,
  findLockDisclosureHeader,
  findUnlockButton,
  findRelatedLockAlert,
  findViewLockedPathButton,
  clickLockDisclosureToggle,
  DEFAULT_BRANCH,
  PROJECT_FULL_PATH,
} from './test_setup';

const LOCK_USER = getProjectInfo.DIRECTORY_LOCKED.data.project.pathLocks.nodes[0].user;

describe('Repository tree header path locks', () => {
  it('locks and unlocks the directory without a page reload', async () => {
    await mountTreeHeaderArea();

    const lockButton = await waitForElement(findLockButton);
    expect(getText(lockButton)).toBe('Lock');

    lockButton.click();
    await waitForModalConfirm();

    await waitForElement(findLockDisclosureToggle);
    await waitForAssertion(() => {
      expect(findToastMessages()).toContain('The directory is locked.');
    });
    await clickLockDisclosureToggle();

    const header = await waitForElement(findLockDisclosureHeader);
    expect(getText(header)).toContain(`Locked by ${LOCK_USER.name}`);

    const unlockButton = await waitForElement(findUnlockButton);
    expect(getText(unlockButton)).toBe('Unlock directory');
    unlockButton.click();
    await waitForModalConfirm();

    await waitForElement(findLockButton);
    await waitForElementToBeNull(findLockDisclosureToggle);
    await waitForAssertion(() => {
      expect(findToastMessages()).toContain('The directory is unlocked.');
    });
  });

  describe('when a parent directory is locked', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).filesDirectoryLocked();
      await mountHeaderArea({ route: `/-/tree/${DEFAULT_BRANCH}/files/ruby` });
    });

    it('points the user at the locked parent instead of offering an unlock', async () => {
      await clickLockDisclosureToggle();

      const alert = await waitForElement(findRelatedLockAlert);
      expect(getText(alert)).toBe(
        'The parent directory "files" is locked. To unlock this directory, unlock "files".',
      );

      const viewLock = findViewLockedPathButton();
      expect(viewLock.getAttribute('href')).toBe(
        `/${PROJECT_FULL_PATH}/-/tree/${DEFAULT_BRANCH}/files`,
      );
      expect(findUnlockButton()).toBe(null);
    });
  });

  describe('when a nested directory is locked', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).nestedDirectoryLocked();
      await mountHeaderArea({ route: `/-/tree/${DEFAULT_BRANCH}/files` });
    });

    it('points the user at the nested lock instead of offering a lock', async () => {
      await clickLockDisclosureToggle();

      const alert = await waitForElement(findRelatedLockAlert);
      expect(getText(alert)).toBe(
        'You cannot lock this directory because "files/ruby" inside it is locked.',
      );

      const viewLock = findViewLockedPathButton();
      expect(viewLock.getAttribute('href')).toBe(
        `/${PROJECT_FULL_PATH}/-/tree/${DEFAULT_BRANCH}/files/ruby`,
      );
      expect(findUnlockButton()).toBe(null);
      expect(findLockButton()).toBe(null);
    });
  });
});
