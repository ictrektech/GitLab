import { GlTruncate } from '@gitlab/ui';
import { nextTick } from 'vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ActiveSessionHistoryQueries from '~/admin/database_diagnostics/components/active_session_history_queries.vue';
import { activeSessionHistoryQueries } from '../mock_data';

describe('ActiveSessionHistoryQueries component', () => {
  let wrapper;

  const findRows = () => wrapper.findAll('tbody tr');
  const findCells = (row) =>
    row.findAll('td').wrappers.map((cell) => cell.text().replace(/\s+/g, ' '));

  const createComponent = ({ queries = activeSessionHistoryQueries } = {}) => {
    wrapper = mountExtended(ActiveSessionHistoryQueries, { propsData: { queries } });
  };

  describe('with attributed and unattributed queries', () => {
    beforeEach(() => {
      createComponent();
    });

    it('lists attributed queries in the order given and the unattributed load last', () => {
      expect(findRows().wrappers.map(findCells)).toEqual([
        [
          'select pg_advisory_lock($1), pg_advisory_unlock($1) Query ID: -7134873239275742000 Show full query',
          '41.5%',
          '0.40',
          '4.00',
        ],
        [
          'Query text not available Query ID: 2056750108613291649',
          '10.4%',
          '0.12',
          'Not available',
        ],
        ['Not attributed to a query', '48.1%', '0.60', '1.00'],
      ]);
    });

    it('copies the query text', () => {
      expect(wrapper.findAllComponents(ClipboardButton).at(0).props()).toMatchObject({
        text: 'select pg_advisory_lock($1), pg_advisory_unlock($1)',
        title: 'Copy query',
      });
    });

    it('offers no copy or toggle for queries without text', () => {
      expect(wrapper.findAllComponents(ClipboardButton)).toHaveLength(1);
      expect(wrapper.findAllByTestId('toggle-query-text')).toHaveLength(1);
    });

    it('shows no query ID for the unattributed load', () => {
      expect(findRows().at(2).find('[data-testid="query-id"]').exists()).toBe(false);
      expect(findRows().at(2).find('[data-testid="unattributed"]').exists()).toBe(true);
    });
  });

  describe('query text', () => {
    const longText = `SELECT "users".* FROM "users" WHERE "users"."id" IN (${Array.from(
      { length: 80 },
      (_, index) => `$${index + 1}`,
    ).join(', ')})`;
    const query = (queryText) => ({ ...activeSessionHistoryQueries[1], query_text: queryText });
    const findToggle = () => wrapper.findByTestId('toggle-query-text');

    describe.each`
      description              | queryText                      | withTooltip
      ${'on one short line'}   | ${'SELECT 1 FROM "projects"'}  | ${true}
      ${'over 200 characters'} | ${longText}                    | ${false}
      ${'over several lines'}  | ${'SELECT 1\nFROM "projects"'} | ${false}
    `('with a query $description', ({ queryText, withTooltip }) => {
      beforeEach(() => {
        createComponent({ queries: [query(queryText)] });
      });

      it('shows it on one line, with a toggle', () => {
        expect(wrapper.findComponent(GlTruncate).props()).toMatchObject({
          text: queryText,
          withTooltip,
        });
        expect(findToggle().text()).toBe('Show full query');
        expect(findToggle().attributes('aria-expanded')).toBe('false');
      });

      it('shows the full text in place and collapses it again', async () => {
        await findToggle().trigger('click');

        expect(wrapper.findComponent(GlTruncate).exists()).toBe(false);
        expect(wrapper.findByTestId('query-text').element.textContent).toBe(queryText);
        expect(findToggle().text()).toBe('Hide full query');
        expect(findToggle().attributes('aria-expanded')).toBe('true');

        await findToggle().trigger('click');
        await nextTick();

        expect(wrapper.findComponent(GlTruncate).exists()).toBe(true);
      });
    });

    describe('with markup in the query text', () => {
      beforeEach(() => {
        createComponent({
          queries: [query('SELECT "<img src=x onerror=alert(1)>" FROM "projects"')],
        });
      });

      it('shows it as text', () => {
        expect(wrapper.find('img').exists()).toBe(false);
        expect(wrapper.findComponent(GlTruncate).props('text')).toBe(
          'SELECT "<img src=x onerror=alert(1)>" FROM "projects"',
        );
      });
    });
  });
});
