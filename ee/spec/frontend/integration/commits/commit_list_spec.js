import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import { groupCommitsByDay } from '~/projects/commits/utils/commit_grouping';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  within,
  getText,
  waitAndClick,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import getCommitListVariants, {
  COMMIT_LIST_ERROR,
} from 'ee_jest/integration/commits/fixture_variants/get_commit_list';
import { commitListResponse } from 'ee_jest/integration/commits/handlers';
import {
  apolloProvider,
  mountCommitListApp,
  findCommitItem,
  findDailyCommits,
  findRefSelector,
  waitForCommitList,
} from './test_setup';

const commits = commitListResponse.data.project.repository.commits.nodes;
const headCommit = commits[0];
const multiDayCommits = getCommitListVariants.MULTIPLE_DAYS.data.project.repository.commits.nodes;

// The Jest process runs in GMT, so the UTC day is also the app's local day.
const dayOf = (commit) => new Date(commit.committedDate).toISOString().slice(0, 10);

const findCommitRows = (container = document.body) =>
  within(container).queryAllByTestId('commit-row');
const findDailyCommitLists = (group) => within(group).queryAllByTestId('daily-commits-list');
const findDailyCommitsDate = (group) => within(group).queryByTestId('daily-commits-date');

describe('Commit list rendering', () => {
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('when browsing the default branch commits', () => {
    beforeEach(async () => {
      mountCommitListApp();
      await waitForCommitList();
    });

    it('renders commits grouped by day with title, SHA and author', () => {
      expect(findDailyCommits().length).toBeGreaterThan(0);

      const item = findCommitItem(headCommit.shortId);
      const titleLink = within(item).queryByTestId('commit-title-link');

      expect(getText(titleLink)).toBe(headCommit.title);
      expect(titleLink.getAttribute('href')).toBe(headCommit.webPath);
      expect(getText(item)).toContain(headCommit.shortId);

      const authorLink = within(item).queryByTestId('commit-author-link');

      expect(getText(authorLink)).toBe(headCommit.author.name);
      expect(authorLink.getAttribute('href')).toBe(headCommit.author.webPath);
    });

    it('shows the ref selector with the current ref', () => {
      expect(getText(findRefSelector())).toContain('feature');
    });

    it('renders a signature badge for a commit signed with an unknown key', () => {
      const badge = within(findCommitItem(headCommit.shortId)).getByTestId('signature-badge');

      expect(getText(badge)).toBe('Unverified');
    });

    it('renders the pipeline status icon only on the commit with a pipeline', () => {
      const withPipeline = findCommitItem(headCommit.shortId);

      expect(within(withPipeline).queryAllByTestId('ci-icon').length).toBeGreaterThan(0);

      const withoutPipeline = findCommitItem(commits[1].shortId);

      expect(within(withoutPipeline).queryAllByTestId('ci-icon')).toHaveLength(0);
    });

    it('collapses commits sharing one day into a single daily group', async () => {
      await waitForAssertion(() => {
        expect(findCommitRows()).toHaveLength(commits.length);
      });

      expect(findDailyCommits()).toHaveLength(1);
    });
  });

  describe('when the ref history spans several days', () => {
    beforeEach(async () => {
      setQueryVariant(getCommitListVariants).multipleDays();
      mountCommitListApp();
      await waitForCommitList();
    });

    it('renders every commit exactly once, grouped under one list per day', async () => {
      const expectedGroups = groupCommitsByDay(multiDayCommits);

      await waitForAssertion(() => {
        expect(findDailyCommits()).toHaveLength(expectedGroups.length);
      });

      expect(findCommitRows()).toHaveLength(multiDayCommits.length);
      findDailyCommits().forEach((group, index) => {
        expect(findDailyCommitLists(group)).toHaveLength(1);
        expect(findCommitRows(group)).toHaveLength(expectedGroups[index].commits.length);
      });
    });

    it('shows the formatted day heading above the commits of that day', () => {
      const [firstGroup] = findDailyCommits();
      const newestCommit = multiDayCommits[0];
      const dateHeading = findDailyCommitsDate(firstGroup);

      expect(dateHeading.getAttribute('datetime')).toBe(dayOf(newestCommit));
      expect(getText(dateHeading)).toBe(
        localeDateFormat.asDate.format(newDate(newestCommit.committedDate)),
      );
      expect(getText(firstGroup)).toContain(newestCommit.title);
    });
  });

  describe('when the commit author has no GitLab account', () => {
    beforeEach(async () => {
      setQueryVariant(getCommitListVariants).noAuthor();
      mountCommitListApp();
      await waitForCommitList();
    });

    it('renders the plain author name', () => {
      const item = findCommitItem(headCommit.shortId);

      expect(within(item).queryByTestId('commit-author-link')).toBe(null);
      expect(getText(item)).toContain(headCommit.authorName);
    });
  });

  describe('when the commit list query fails', () => {
    beforeEach(() => {
      setQueryVariant(getCommitListVariants).error();
      mountCommitListApp();
    });

    it('shows an alert', async () => {
      await waitForAssertion(() => {
        expect(getText(document.body)).toContain(COMMIT_LIST_ERROR);
      });
    });
  });

  describe('when the branch name contains a slash', () => {
    describe('when visiting the branch via direct URL', () => {
      beforeEach(async () => {
        mountCommitListApp({ ref: 'improve/awesome' });
        await waitForCommitList();
      });

      it('loads commits for the branch', () => {
        expect(getText(findRefSelector())).toContain('improve/awesome');
        expect(lastRequestVariables('getCommitList').ref).toBe('refs/heads/improve/awesome');
      });
    });

    describe('when selecting the branch in the ref selector', () => {
      beforeEach(async () => {
        mountCommitListApp();
        await waitForCommitList();

        await waitAndClick(() => findRefSelector().querySelector('button'));
        await waitAndClick(
          () =>
            within(findRefSelector()).queryAllByRole('option', { name: /improve\/awesome/ })[0] ??
            null,
        );
      });

      it('loads the branch commits without a reload', async () => {
        await waitForAssertion(() => {
          expect(lastRequestVariables('getCommitList').ref).toBe('refs/heads/improve/awesome');
        });
        expect(getText(findRefSelector())).toContain('improve/awesome');
      });
    });
  });

  describe('when the URL is scoped to a path', () => {
    beforeEach(async () => {
      mountCommitListApp({ path: 'files/ruby' });
      await waitForCommitList();
    });

    it('sends the path as a query variable', () => {
      expect(lastRequestVariables('getCommitList').path).toBe('files/ruby');
    });
  });
});
