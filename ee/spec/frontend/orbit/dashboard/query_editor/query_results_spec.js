import { GlEmptyState } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import QueryResults from 'ee/orbit/dashboard/query_editor/query_results.vue';
import QueryResultsTable from 'ee/orbit/components/query_results_table.vue';
import { downloadCsv } from 'ee/orbit/utils/csv_export';

jest.mock('ee/orbit/utils/csv_export');

describe('QueryResults', () => {
  let wrapper;

  const rows = [
    { 'u.username': 'root', 'mr.title': 'Fix the pipeline graph' },
    { 'u.username': 'dev', 'mr.title': 'Cache project tree lookups' },
  ];

  const createComponent = (props = {}) => {
    wrapper = mountExtended(QueryResults, {
      propsData: { rows, durationMs: 1250, hasMoreRows: false, canAskDuo: true, ...props },
    });
  };

  const findSummary = () => wrapper.findByTestId('query-results-summary');
  const findRowLimit = () => wrapper.findByTestId('query-row-limit');
  const findTable = () => wrapper.findComponent(QueryResultsTable);
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findButton = (name) => wrapper.findByRole('button', { name });

  describe('with all the rows that match', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the row count, the run time, and the rows', () => {
      expect(findSummary().text()).toBe('2 rows · 1,250 ms');
      expect(findTable().props('rows')).toEqual(rows);
      expect(findRowLimit().exists()).toBe(false);
      expect(findEmptyState().exists()).toBe(false);
    });

    describe('and the user exports the rows', () => {
      beforeEach(async () => {
        await findButton('Export CSV').trigger('click');
      });

      it('downloads them as CSV', () => {
        expect(downloadCsv).toHaveBeenCalledWith(rows);
      });
    });
  });

  describe('with one row', () => {
    beforeEach(() => {
      createComponent({ rows: [rows[0]] });
    });

    it('shows the singular row count', () => {
      expect(findSummary().text()).toBe('1 row · 1,250 ms');
    });
  });

  describe('when more rows match than the query returns', () => {
    beforeEach(() => {
      createComponent({ hasMoreRows: true });
    });

    it('says to raise the LIMIT or use SKIP', () => {
      expect(findRowLimit().text()).toBe(
        'More rows match this query. Raise the LIMIT, or use SKIP to get the next page.',
      );
    });
  });

  describe('with no rows', () => {
    beforeEach(() => {
      createComponent({ rows: [] });
    });

    it('shows the no rows state with no table and no export', () => {
      expect(findEmptyState().props('title')).toBe('No rows match this query');
      expect(findTable().exists()).toBe(false);
      expect(findRowLimit().exists()).toBe(false);
      expect(findButton('Export CSV').exists()).toBe(false);
    });

    it.each([
      ['Ask GitLab Duo why', 'ask-duo-why'],
      ['Check the schema', 'check-schema'],
    ])('emits an event when the user selects %s', async (name, event) => {
      await findButton(name).trigger('click');

      expect(wrapper.emitted(event)).toHaveLength(1);
    });
  });

  describe('with no rows and no GitLab Duo', () => {
    beforeEach(() => {
      createComponent({ rows: [], canAskDuo: false });
    });

    it('offers only the schema', () => {
      expect(findButton('Ask GitLab Duo why').exists()).toBe(false);
      expect(findButton('Check the schema').exists()).toBe(true);
    });
  });
});
