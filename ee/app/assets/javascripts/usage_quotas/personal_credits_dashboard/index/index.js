import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createApolloClient from '~/lib/graphql';
import PersonalCreditsDashboardApp from './components/app.vue';

/**
 * @param {HTMLElement} el
 */
export function initPersonalCreditsDashboard(el) {
  if (!el) return null;

  const { groupsWithGitlabCredits } = el.dataset;

  Vue.use(VueApollo);
  const apolloProvider = new VueApollo({
    defaultClient: createApolloClient(),
  });

  return new Vue({
    el,
    apolloProvider,
    name: 'PersonalCreditsDashboardRoot',
    provide: {
      groups: JSON.parse(groupsWithGitlabCredits),
    },
    render(createElement) {
      return createElement(PersonalCreditsDashboardApp);
    },
  });
}
