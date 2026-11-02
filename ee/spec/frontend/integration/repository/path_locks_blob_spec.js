import {
  screen,
  findToastMessages,
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
  waitForModalConfirm,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { snapshotRequests, expectGraphQLCalls } from 'ee_jest/integration/core/operation_helpers';
import { getProjectInfo } from 'ee_jest/integration/repository/fixture_variants';
import {
  mountBlobHeaderArea,
  mountHeaderArea,
  findLockButton,
  findLockDisclosureToggle,
  findLockDisclosureHeader,
  findUnlockButton,
  findNoPermissionMessage,
  findRelatedLockAlert,
  findViewLockedPathButton,
  clickLockDisclosureToggle,
  findLockUserCard,
  findLockUserLink,
  findBlobOverflowMenuToggle,
  findReplaceItem,
  findDeleteItem,
  DEFAULT_BRANCH,
  PROJECT_FULL_PATH,
} from './test_setup';

const LOCK_USER = getProjectInfo.LOCKED.data.project.pathLocks.nodes[0].user;
const OTHER_LOCK_USER = getProjectInfo.FILE_LOCKED_BY_OTHER.data.project.pathLocks.nodes[0].user;

const findBlobOverflowMenu = () => screen.queryByTestId('blob-overflow-menu');

describe('Repository blob header path locks', () => {
  it('locks and unlocks the file without a page reload', async () => {
    await mountBlobHeaderArea();

    const lockButton = await waitForElement(findLockButton);
    expect(getText(lockButton)).toBe('Lock');

    const baseline = snapshotRequests();
    lockButton.click();
    await waitForModalConfirm();

    await waitForElement(findLockDisclosureToggle);

    // The lock lands through the mutation plus one projectInfo refetch; the
    // blob controls stay served from the cache.
    expectGraphQLCalls(baseline, {
      expect: ['toggleLock', 'getProjectInfoEE'],
      forbid: ['getBlobControls'],
    });

    await waitForAssertion(() => {
      expect(findToastMessages()).toContain('The file is locked.');
    });

    await clickLockDisclosureToggle();
    const header = await waitForElement(findLockDisclosureHeader);
    expect(getText(header)).toContain(`Locked by ${LOCK_USER.name}`);

    const unlockButton = await waitForElement(findUnlockButton);
    expect(getText(unlockButton)).toBe('Unlock file');
    unlockButton.click();
    await waitForModalConfirm();

    await waitForElement(findLockButton);
    await waitForElementToBeNull(findLockDisclosureToggle);
    await waitForAssertion(() => {
      expect(findToastMessages()).toContain('The file is unlocked.');
    });
  });

  describe('when the file is already locked by the current user', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).locked();
      await mountBlobHeaderArea();
    });

    it('shows the lock author card and lazy-loads the extra user details', async () => {
      await clickLockDisclosureToggle();

      const header = await waitForElement(findLockDisclosureHeader);
      expect(getText(header)).toContain(`Locked by ${LOCK_USER.name}`);
      // The lock timestamp renders as a relative time next to the header.
      expect(header.querySelector('time')).not.toBe(null);

      const link = await waitForElement(findLockUserLink);
      expect(link.getAttribute('href')).toBe(LOCK_USER.webPath);

      // Opening the disclosure fetches extra details from /api/v4/users/:id.
      await waitForAssertion(() => {
        expect(getText(findLockUserCard())).toContain('Release manager');
      });
      const cardText = getText(findLockUserCard());
      expect(cardText).toContain('GitLab');
      expect(cardText).toContain('Terminal 3');
      expect(cardText).toContain('2:00 PM');
    });
  });

  describe('when the file is locked by someone else', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).fileLockedByOther();
      await mountBlobHeaderArea();
    });

    it('shows who holds the lock and denies unlocking', async () => {
      await clickLockDisclosureToggle();

      const message = await waitForElement(findNoPermissionMessage);
      expect(getText(message)).toBe('You do not have permission to unlock this file.');
      expect(findUnlockButton()).toBe(null);
      expect(getText(findLockDisclosureHeader())).toContain(`Locked by ${OTHER_LOCK_USER.name}`);
    });
  });

  describe('when a parent directory is locked', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).directoryLocked();
      await mountHeaderArea({ route: `/-/blob/${DEFAULT_BRANCH}/encoding/test.txt` });
    });

    it('points the user at the locked directory instead of offering an unlock', async () => {
      await clickLockDisclosureToggle();

      const alert = await waitForElement(findRelatedLockAlert);
      expect(getText(alert)).toBe(
        'The parent directory "encoding" is locked. To unlock this file, unlock "encoding".',
      );

      const viewLock = findViewLockedPathButton();
      expect(viewLock.getAttribute('href')).toBe(
        `/${PROJECT_FULL_PATH}/-/tree/${DEFAULT_BRANCH}/encoding`,
      );
      expect(findUnlockButton()).toBe(null);
    });
  });

  describe('when a different path is locked', () => {
    beforeEach(async () => {
      // Lock on "encoding"; VERSION must not match it (prefix matching uses
      // "encoding/", so only files inside the directory inherit the lock).
      setQueryVariant(getProjectInfo).directoryLocked();
      await mountBlobHeaderArea();
    });

    it('still offers a plain Lock', async () => {
      // The Lock button only renders once projectInfo has landed, so its
      // presence makes the toggle's absence meaningful.
      const lockButton = await waitForElement(findLockButton);
      expect(getText(lockButton)).toBe('Lock');
      expect(findLockDisclosureToggle()).toBe(null);
    });
  });

  describe('File actions when the file is locked by someone else', () => {
    describe('on the default branch', () => {
      beforeEach(async () => {
        setQueryVariant(getProjectInfo).fileLockedByOther();
        await mountBlobHeaderArea();
      });

      it('disables Replace and Delete', async () => {
        // The Locked toggle is served by the same projectInfo query the menu
        // reads, so its presence means the lock state has landed.
        await waitForElement(findLockDisclosureToggle);
        await waitAndClick(findBlobOverflowMenuToggle);

        const replaceItem = await waitForElement(findReplaceItem);
        expect(replaceItem.disabled).toBe(true);
        expect(findDeleteItem().disabled).toBe(true);
      });
    });

    describe('on a non-default branch', () => {
      beforeEach(async () => {
        setQueryVariant(getProjectInfo).fileLockedByOther();
        await mountBlobHeaderArea({ currentRef: 'feature' });
      });

      it('keeps Replace and Delete enabled', async () => {
        await waitForElement(findLockDisclosureToggle);
        await waitAndClick(findBlobOverflowMenuToggle);

        const replaceItem = await waitForElement(findReplaceItem);
        expect(replaceItem.disabled).toBe(false);
        expect(findDeleteItem().disabled).toBe(false);
      });
    });
  });

  describe('when a reporter views a file inside a locked directory', () => {
    beforeEach(async () => {
      setQueryVariant(getProjectInfo).directoryLockedAsReporter();
      await mountHeaderArea({ route: `/-/blob/${DEFAULT_BRANCH}/encoding/test.txt` });
    });

    // Regression test for !250523: users who cannot create locks must still
    // see the lock state of a parent directory.
    it('still surfaces the parent directory lock', async () => {
      await clickLockDisclosureToggle();

      const alert = await waitForElement(findRelatedLockAlert);
      expect(getText(alert)).toBe(
        'The parent directory "encoding" is locked. To unlock this file, unlock "encoding".',
      );
      expect(findUnlockButton()).toBe(null);
    });
  });

  describe('when file locks are not licensed', () => {
    let baseline;

    beforeEach(async () => {
      baseline = snapshotRequests();
      await mountBlobHeaderArea({ glLicensedFeatures: { fileLocks: false } });
    });

    it('renders no lock button', async () => {
      await waitForElement(findBlobOverflowMenu);
      // The overflow menu still fetches project info, so the page has settled
      // once both operations landed; only then is the absence meaningful.
      await waitForAssertion(() => {
        expectGraphQLCalls(baseline, {
          expect: ['getBlobControls', 'getProjectInfoEE'],
          forbid: [],
        });
      });

      expect(findLockButton()).toBe(null);
      expect(findLockDisclosureToggle()).toBe(null);
    });
  });

  describe('when the user cannot create locks and none exist', () => {
    let baseline;

    beforeEach(async () => {
      setQueryVariant(getProjectInfo).cannotCreateLock();
      baseline = snapshotRequests();
      await mountBlobHeaderArea();
    });

    it('renders no lock button', async () => {
      await waitForElement(findBlobOverflowMenu);
      await waitForAssertion(() => {
        expectGraphQLCalls(baseline, { expect: ['getProjectInfoEE'], forbid: [] });
      });

      expect(findLockButton()).toBe(null);
      expect(findLockDisclosureToggle()).toBe(null);
    });
  });
});
