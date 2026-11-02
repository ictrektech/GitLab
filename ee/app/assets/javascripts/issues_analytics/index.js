import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createDefaultClient from '~/lib/graphql';
import { queryToObject } from '~/lib/utils/url_utility';
import { pinia } from '~/pinia/instance';
import IssuesAnalytics from './components/issues_analytics.vue';
import { useIssuesAnalytics } from './stores';

Vue.use(VueApollo);

const apolloProvider = new VueApollo({
  defaultClient: createDefaultClient(
    {},
    {
      cacheConfig: {
        typePolicies: {
          Group: { fields: { flowMetrics: { merge: true } } },
          Project: { fields: { flowMetrics: { merge: true } } },
        },
      },
    },
  ),
});

export default () => {
  const el = document.querySelector('#js-issues-analytics');
  const filterBlockEl = document.querySelector('.issues-filters');

  if (!el) return null;

  const {
    fullPath,
    type,
    endpoint,
    filtersEmptyStateSvgPath,
    issuesPageEndpoint,
    hasIssuesCompletedFeature,
    canCreateProjects,
    newIssuePath,
    newProjectPath,
    showNewIssueDropdown,
    signInPath,
    groupId,
  } = el.dataset;

  // Set default filters from URL
  const filters = queryToObject(window.location.search, { gatherArrays: true });
  useIssuesAnalytics(pinia).setFilters(filters);

  return initVueApp({
    el,
    name: 'IssuesAnalytics',
    apolloProvider,
    pinia,
    provide: {
      fullPath,
      type,
      hasIssuesCompletedFeature: parseBoolean(hasIssuesCompletedFeature),
      endpoint,
      issuesPageEndpoint,
      filtersEmptyStateSvgPath,
      canCreateProjects: parseBoolean(canCreateProjects),
      newIssuePath,
      newProjectPath,
      showNewIssueDropdown: parseBoolean(showNewIssueDropdown),
      showNewIssueLink: false,
      signInPath,
      groupId,
    },
    component: IssuesAnalytics,
    props: {
      filterBlockEl,
    },
  });
};
