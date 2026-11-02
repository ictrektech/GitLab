<script>
import { queryToObject, updateHistory, setUrlParams, removeParams } from '~/lib/utils/url_utility';
import { InternalEvents } from '~/tracking';
import AgentArtifactsTable from './agent_artifacts_table.vue';
import AgentArtifactsFilteredSearch from './agent_artifacts_filtered_search.vue';
import SessionDetailsDrawer from './session_details_drawer.vue';

export default {
  name: 'AgentArtifactsApp',
  components: {
    AgentArtifactsTable,
    AgentArtifactsFilteredSearch,
    SessionDetailsDrawer,
  },
  mixins: [InternalEvents.mixin()],
  data() {
    return {
      activeItem: null,
      filter: {},
      selectedEvent: null,
      // Session id from `?session=`, so a link from the dashboard opens the
      // drawer rather than the session's own page, which 404s for anyone who
      // did not run it. The table consumes this once and then ignores it.
      deepLinkedSessionId: queryToObject(window.location.search).session || null,
    };
  },
  methods: {
    // Keep `?session=` pointing at whatever is actually open, so the URL can be
    // copied or refreshed and land back on the same session. `replace` rather
    // than push: opening and closing a drawer should not fill the back button
    // with states the user then has to walk out of.
    syncSessionParam(id) {
      updateHistory({
        url: id ? setUrlParams({ session: id }) : removeParams(['session']),
        replace: true,
      });
    },
    handleRowClick(item) {
      this.activeItem = item;
      this.selectedEvent = null;
      this.deepLinkedSessionId = null;
      this.syncSessionParam(item.sessionId);
    },
    handleFilter(filter) {
      this.activeItem = null;
      this.selectedEvent = null;
      this.filter = filter;
      this.syncSessionParam(null);
    },
    handleDrawerClose() {
      this.activeItem = null;
      this.selectedEvent = null;
      this.syncSessionParam(null);
    },
    handleEventSelect(event) {
      this.trackEvent('open_audit_event_on_ai_audit_events_report');
      this.selectedEvent = event;
    },
    // A deep link can name a session that is not in the results. Drop the
    // param rather than leave the address bar pointing at nothing on screen.
    handleDeepLinkMissed() {
      this.deepLinkedSessionId = null;
      this.syncSessionParam(null);
    },
  },
};
</script>
<template>
  <div>
    <agent-artifacts-filtered-search class="gl-mt-5" @filter="handleFilter" />

    <agent-artifacts-table
      class="gl-mt-5"
      :active-item="activeItem"
      :filter="filter"
      :deep-linked-session-id="deepLinkedSessionId"
      @row-click="handleRowClick"
      @deep-link-missed="handleDeepLinkMissed"
    />

    <session-details-drawer
      v-if="activeItem"
      :active-item="activeItem"
      :selected-event="selectedEvent"
      @close="handleDrawerClose"
      @select="handleEventSelect"
      @back="selectedEvent = null"
    />
  </div>
</template>
