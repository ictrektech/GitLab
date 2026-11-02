import { defineStore } from 'pinia';
import { setUrlParams, queryToObject, visitUrl } from '~/lib/utils/url_utility';
import { parseAuditEventSearchQuery, createAuditEventSearchQuery } from '../utils';

export const useAuditEvents = defineStore('auditEvents', {
  state() {
    return {
      filterValue: [],

      startDate: null,
      endDate: null,

      sortBy: null,
    };
  },
  getters: {
    /**
     * Returns the CSV export href for given base path and search filters
     * @param {string} exportUrl
     * @returns {string}
     */
    buildExportHref: (state) => (exportUrl) => {
      return setUrlParams(
        createAuditEventSearchQuery({
          filterValue: state.filterValue,
          startDate: state.startDate,
          endDate: state.endDate,
        }),
        { url: exportUrl },
      );
    },
  },
  actions: {
    initializeAuditEvents() {
      const {
        entity_id: entityId = null,
        entity_username: entityUsername = null,
        author_username: authorUsername = null,
        entity_type: type = null,
        created_after: startDate = null,
        created_before: endDate = null,
        sort: sortBy = null,
      } = parseAuditEventSearchQuery(
        queryToObject(window.location.search, { legacySpacesDecode: true }),
      );

      const data = entityId ?? entityUsername ?? authorUsername;
      this.filterValue = type && data ? [{ type, value: { data, operator: '=' } }] : [];
      this.startDate = startDate;
      this.endDate = endDate;
      this.sortBy = sortBy;
    },
    searchForAuditEvents() {
      visitUrl(setUrlParams(createAuditEventSearchQuery(this)));
    },
    setDateRange({ startDate, endDate }) {
      this.startDate = startDate;
      this.endDate = endDate;
      this.searchForAuditEvents();
    },
    setFilterValue(filterValue) {
      this.filterValue = filterValue;
    },
    setSortBy(sortBy) {
      this.sortBy = sortBy;
      this.searchForAuditEvents();
    },
  },
});
