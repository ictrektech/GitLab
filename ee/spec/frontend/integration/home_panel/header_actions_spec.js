import {
  getText,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant, setUserSession } from 'ee_jest/integration/helpers/setup_utils';
import { expectGraphQLCalls, snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import { getProjectByPath } from 'ee_jest/integration/home_panel/fixture_variants';
import {
  mountHomePanel,
  findActionsDropdown,
  findNotificationsDropdown,
  findDropdownToggle,
  PROJECT_ID,
} from './test_setup';

const COPY_ID_TEXT = `Copy project ID: ${PROJECT_ID}`;

const openActionsDropdown = async () => {
  const dropdown = await waitForElement(findActionsDropdown);
  const toggle = findDropdownToggle(dropdown);
  toggle.click();

  await waitForAssertion(() => expect(toggle.getAttribute('aria-expanded')).toBe('true'));

  return dropdown;
};

describe('Project home panel actions dropdown', () => {
  describe.each`
    membership             | variantKey           | leave    | edit
    ${'direct maintainer'} | ${'base'}            | ${true}  | ${true}
    ${'direct developer'}  | ${'developer'}       | ${true}  | ${false}
    ${'non-member'}        | ${'nonMember'}       | ${false} | ${false}
    ${'group developer'}   | ${'groupDeveloper'}  | ${false} | ${false}
    ${'group maintainer'}  | ${'groupMaintainer'} | ${false} | ${true}
  `('when signed in as a $membership', ({ variantKey, leave, edit }) => {
    it('shows the correct items', async () => {
      setQueryVariant(getProjectByPath)[variantKey]();
      mountHomePanel();

      const dropdown = await openActionsDropdown();
      const text = getText(dropdown);

      expect(text).toContain(COPY_ID_TEXT);
      expect(text.includes('Leave project')).toBe(leave);
      expect(text.includes('Edit')).toBe(edit);
    });
  });

  describe('when signed out', () => {
    beforeEach(() => {
      setUserSession(false);
    });

    it('shows only the copy project ID item and skips the project query', async () => {
      const baseline = snapshotRequests();
      mountHomePanel();

      const dropdown = await openActionsDropdown();
      const text = getText(dropdown);

      expect(text).toContain(COPY_ID_TEXT);
      expect(text).not.toContain('Leave project');
      expect(text).not.toContain('Edit');
      // The dropdown rendered from default data, so the page settled without the query.
      expectGraphQLCalls(baseline, { expect: [], forbid: ['getProjectByPath'] });
      // The notifications dropdown is signed-in only.
      expect(findNotificationsDropdown()).toBeNull();
    });
  });
});
