import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

const OPEN_ITEMS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];
const ALL_ITEMS = [...OPEN_ITEMS, WORK_ITEMS.CLOSED];

describe('Work items list - state tabs', () => {
  useFilterSpec();

  describe('when arriving on a URL with state=closed', () => {
    beforeEach(() => {
      useListFixture('CLOSED');
      mountListWithQuery('?state=closed');
    });

    it('requests and shows only closed items', async () => {
      await expectListToShow([WORK_ITEMS.CLOSED]);

      expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ state: 'closed' });
    });
  });

  describe('when arriving on a URL with state=all', () => {
    beforeEach(() => {
      useListFixture('ALL');
      mountListWithQuery('?state=all');
    });

    it('requests and shows open and closed items', async () => {
      await expectListToShow(ALL_ITEMS);

      expect(lastRequestVariables('getWorkItemsSlimEE')).toMatchObject({ state: 'all' });
    });
  });

  describe('when arriving with no state in the URL', () => {
    beforeEach(() => {
      // An empty query makes the app sync default params to the URL after preferences load,
      // which lands late in non-first tests and overrides the tab click. Any param skips it.
      // https://gitlab.com/gitlab-org/gitlab/-/work_items/630804
      mountListWithQuery('?sort=created_date');
    });

    it('hides closed items by default', async () => {
      await expectListToShow(OPEN_ITEMS);
    });
  });
});
