import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import createDefaultClient from '~/lib/graphql';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { MAX_HEADERS } from './constants';
import AuditEventsApp from './components/audit_events_app.vue';
import { useAuditEvents } from './store';

Vue.use(VueApollo);

export default (selector) => {
  const el = document.querySelector(selector);

  if (!el) {
    return false;
  }

  const {
    events,
    isLastPage,
    filterTokenOptions,
    exportUrl = '',
    showStreams,
    groupPath,
    emptyStateSvgPath,
    filterViewOnly,
    filterTokenValues,
    auditEventDefinitions,
    auditEventsDetailsDrawerEnabled,
  } = el.dataset;

  const parsedFilterTokenOptions = JSON.parse(filterTokenOptions).map((filterTokenOption) =>
    convertObjectPropsToCamelCase(filterTokenOption),
  );
  const apolloProvider = new VueApollo({
    defaultClient: createDefaultClient(),
  });

  useAuditEvents(pinia).initializeAuditEvents();

  return initVueApp({
    el,
    name: 'AuditEventsView',
    pinia,
    provide: {
      events: JSON.parse(events) || [],
      isLastPage: parseBoolean(isLastPage) || false,
      filterTokenOptions: parsedFilterTokenOptions,
      exportUrl,
      showStreams: parseBoolean(showStreams) || false,
      maxHeaders: MAX_HEADERS,
      groupPath,
      // group level and project level are mutually exclusive.
      isProject: !groupPath,
      emptyStateSvgPath,
      filterViewOnly: parseBoolean(filterViewOnly) || false,
      filterTokenValues: filterTokenValues ? JSON.parse(filterTokenValues) : [],
      auditEventDefinitions: auditEventDefinitions ? JSON.parse(auditEventDefinitions) : [],
      auditEventsDetailsDrawerEnabled: parseBoolean(auditEventsDetailsDrawerEnabled),
    },
    apolloProvider,
    component: AuditEventsApp,
  });
};
