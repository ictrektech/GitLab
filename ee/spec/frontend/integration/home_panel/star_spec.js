import {
  getText,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant, setUserSession } from 'ee_jest/integration/helpers/setup_utils';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import { setStarStatus } from 'ee_jest/integration/home_panel/fixture_variants';
import {
  mountHomePanel,
  findStarButton,
  findStarCount,
  PROJECT_ID,
  SIGN_IN_PATH,
} from './test_setup';

describe('Project home panel star button', () => {
  it('toggles the star and updates the star count without a page reload', async () => {
    mountHomePanel();

    const starButton = await waitForElement(findStarButton);
    expect(getText(starButton)).toBe('Star');
    expect(getText(findStarCount())).toBe('0');

    // Let the mount-time project query land before baselining, so forbidding it
    // below proves the mutation updated the count without a refetch.
    await waitForAssertion(() => lastRequestVariables('getProjectByPath'));

    const baseline = snapshotRequests();
    starButton.click();

    await waitForAssertion(() => expect(getText(findStarCount())).toBe('1'));
    expect(getText(findStarButton())).toBe('Unstar');
    expectGraphQLCalls(baseline, { expect: ['setStarStatus'], forbid: ['getProjectByPath'] });
    expect(lastRequestVariables('setStarStatus')).toEqual({
      projectId: `gid://gitlab/Project/${PROJECT_ID}`,
      starred: true,
    });

    findStarButton().click();

    await waitForAssertion(() => expect(getText(findStarCount())).toBe('0'));
    expect(getText(findStarButton())).toBe('Star');
    expect(lastRequestVariables('setStarStatus')).toMatchObject({ starred: false });
  });

  it('renders the already-starred state the page reloads into', async () => {
    mountHomePanel({ starred: 'true', starCount: '1' });

    const starButton = await waitForElement(findStarButton);
    expect(getText(starButton)).toBe('Unstar');
    expect(getText(findStarCount())).toBe('1');
  });

  describe('when the mutation fails', () => {
    beforeEach(() => {
      setQueryVariant(setStarStatus).error();
      mountHomePanel();
    });

    it('shows an error toast and keeps the star state', async () => {
      const starButton = await waitForElement(findStarButton);
      starButton.click();

      await waitForAssertion(() =>
        expect(getText(document.body)).toContain('Star toggle failed. Try again later.'),
      );
      expect(getText(findStarButton())).toBe('Star');
      expect(getText(findStarCount())).toBe('0');
    });
  });

  describe('when signed out', () => {
    beforeEach(() => {
      setUserSession(false);
      mountHomePanel();
    });

    it('links to sign-in instead of starring', async () => {
      const starButton = await waitForElement(findStarButton);
      expect(starButton.getAttribute('href')).toBe(SIGN_IN_PATH);
    });
  });
});
