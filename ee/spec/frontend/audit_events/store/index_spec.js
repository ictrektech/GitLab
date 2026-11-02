import { createTestingPinia } from '@pinia/testing';
import { useAuditEvents } from 'ee/audit_events/store';
import setWindowLocation from 'helpers/set_window_location_helper';
import * as urlUtility from '~/lib/utils/url_utility';

describe('Audit events store', () => {
  let store;
  const startDate = new Date('March 13, 2020 12:00:00');
  const endDate = new Date('April 13, 2020 12:00:00');

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useAuditEvents();
  });

  describe('initial state', () => {
    it('has empty filters, dates and sorting', () => {
      expect(store.filterValue).toEqual([]);
      expect(store.startDate).toBeNull();
      expect(store.endDate).toBeNull();
      expect(store.sortBy).toBeNull();
    });
  });

  describe('getters', () => {
    describe('buildExportHref', () => {
      const exportUrl = 'https://example.com/audit_reports.csv';

      describe('with empty state', () => {
        it('returns the export href', () => {
          expect(store.buildExportHref(exportUrl)).toEqual('https://example.com/audit_reports.csv');
        });
      });

      describe('with filters and dates', () => {
        it('returns the export url', () => {
          store.filterValue = [{ type: 'user', value: { data: '@root', operator: '=' } }];
          store.startDate = new Date(2020, 1, 2);
          store.endDate = new Date(2020, 1, 30);

          expect(store.buildExportHref(exportUrl)).toEqual(
            'https://example.com/audit_reports.csv?' +
              'created_after=2020-02-02&created_before=2020-03-01' +
              '&entity_type=User&entity_username=root',
          );
        });
      });
    });
  });

  describe('actions', () => {
    describe('setDateRange', () => {
      beforeEach(() => {
        jest.spyOn(store, 'searchForAuditEvents').mockImplementation();
      });

      it('sets the dates and searches for audit events', () => {
        store.setDateRange({ startDate, endDate });

        expect(store.startDate).toBe(startDate);
        expect(store.endDate).toBe(endDate);
        expect(store.searchForAuditEvents).toHaveBeenCalledTimes(1);
      });
    });

    describe('setSortBy', () => {
      beforeEach(() => {
        jest.spyOn(store, 'searchForAuditEvents').mockImplementation();
      });

      it('sets the sorting and searches for audit events', () => {
        store.setSortBy('created_asc');

        expect(store.sortBy).toBe('created_asc');
        expect(store.searchForAuditEvents).toHaveBeenCalledTimes(1);
      });
    });

    describe('setFilterValue', () => {
      it('sets the filter value', () => {
        const filterValue = [{ type: 'User', value: { data: '@root', operator: '=' } }];

        store.setFilterValue(filterValue);

        expect(store.filterValue).toEqual(filterValue);
      });
    });

    describe('searchForAuditEvents', () => {
      let spy;

      beforeEach(() => {
        setWindowLocation('https://test/');
        spy = jest.spyOn(urlUtility, 'visitUrl').mockReturnValue({});
      });

      afterEach(() => {
        spy.mockRestore();
      });

      describe('with a default state', () => {
        it('should call visitUrl without a search query', () => {
          store.searchForAuditEvents();

          expect(spy).toHaveBeenCalledWith('https://test/');
        });
      });

      describe('with a state that has a search query', () => {
        beforeEach(() => {
          store.sortBy = 'created_asc';
        });

        it('should call visitUrl with a search query', () => {
          store.searchForAuditEvents();

          expect(spy).toHaveBeenCalledWith('https://test/?sort=created_asc');
        });
      });
    });

    describe('initializeAuditEvents', () => {
      describe('with an empty search query', () => {
        beforeEach(() => {
          setWindowLocation('?');
        });

        it('resets the state with empty dates', () => {
          store.initializeAuditEvents();

          expect(store.filterValue).toEqual([]);
          expect(store.startDate).toBeNull();
          expect(store.endDate).toBeNull();
          expect(store.sortBy).toBeNull();
        });
      });

      describe('with a full search query', () => {
        beforeEach(() => {
          setWindowLocation(
            '?sort=created_desc&entity_type=Project&entity_id=44&created_after=2020-06-05&created_before=2020-06-25',
          );
        });

        it('sets the state from the query data', () => {
          store.initializeAuditEvents();

          expect(store.filterValue).toEqual([
            { type: 'project', value: { data: '44', operator: '=' } },
          ]);
          expect(store.startDate).toEqual(new Date('2020-06-05T00:00:00.000Z'));
          expect(store.endDate).toEqual(new Date('2020-06-25T00:00:00.000Z'));
          expect(store.sortBy).toBe('created_desc');
        });
      });

      describe.each`
        queryKey             | queryValue | expectedData
        ${'entity_id'}       | ${'1'}     | ${'1'}
        ${'entity_username'} | ${'abc'}   | ${'@abc'}
        ${'author_username'} | ${'abc'}   | ${'@abc'}
      `('with $queryKey in the search query', ({ queryKey, queryValue, expectedData }) => {
        beforeEach(() => {
          setWindowLocation(`?entity_type=User&${queryKey}=${queryValue}`);
        });

        it('sets the filter value', () => {
          store.initializeAuditEvents();

          expect(store.filterValue).toEqual([
            { type: 'user', value: { data: expectedData, operator: '=' } },
          ]);
        });
      });
    });
  });
});
