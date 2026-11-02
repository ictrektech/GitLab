import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import FilteredSearchIssueAnalytics from 'ee/issues_analytics/filtered_search_issues_analytics';
import IssuableFilteredSearchTokenKeys from 'ee/filtered_search/issuable_filtered_search_token_keys';
import { useIssuesAnalytics } from 'ee/issues_analytics/stores';
import { pinia } from '~/pinia/instance';
import { historyPushState } from '~/lib/utils/common_utils';

jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  historyPushState: jest.fn(),
}));

describe('FilteredSearchIssueAnalytics', () => {
  describe('Token keys', () => {
    const fixture = `<div class="filtered-search-box-input-container"><input class="filtered-search" /></div>`;
    let component;
    let availableTokens;
    let enableMultipleAssigneesSpy;

    const supportedTokenKeys = ['author', 'assignee', 'milestone', 'label', 'epic', 'weight'];

    describe.each`
      shouldEnableMultipleAssignees | hasIssuesCompletedFeature
      ${false}                      | ${false}
      ${true}                       | ${true}
    `(
      'when hasIssuesCompletedFeature=$hasIssuesCompletedFeature',
      ({ hasIssuesCompletedFeature, shouldEnableMultipleAssignees }) => {
        beforeEach(() => {
          setHTMLFixture(fixture);

          enableMultipleAssigneesSpy = jest
            .spyOn(IssuableFilteredSearchTokenKeys, 'enableMultipleAssignees')
            .mockImplementation();
          component = new FilteredSearchIssueAnalytics({ hasIssuesCompletedFeature });
          availableTokens = component.filteredSearchTokenKeys;
        });

        afterEach(() => {
          component = null;

          resetHTMLFixture();
          enableMultipleAssigneesSpy.mockRestore();
        });

        it('should only include the supported token keys', () => {
          const availableTokenKeys = availableTokens.getKeys();

          expect(availableTokenKeys).toEqual(supportedTokenKeys);
        });

        it(`should ${shouldEnableMultipleAssignees ? '' : 'not'} enable multiple assignees`, () => {
          expect(enableMultipleAssigneesSpy).toHaveBeenCalledTimes(
            shouldEnableMultipleAssignees ? 1 : 0,
          );
        });
      },
    );
  });

  describe('updateObject', () => {
    beforeEach(() => {
      setHTMLFixture(
        `<div class="filtered-search-box-input-container"><input class="filtered-search" /></div>`,
      );
    });

    afterEach(() => {
      resetHTMLFixture();
    });

    it('pushes the path to the history and updates the filters in the store', () => {
      const store = useIssuesAnalytics(pinia);
      const component = new FilteredSearchIssueAnalytics({});

      component.updateObject('?author_username=bob&label_name[]=a&label_name[]=b');

      expect(historyPushState).toHaveBeenCalledWith(
        '?author_username=bob&label_name[]=a&label_name[]=b',
      );
      expect(store.filters).toEqual({ author_username: 'bob', label_name: ['a', 'b'] });
    });
  });
});
