import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import apolloProvider from '~/repository/graphql';
import projectPathQuery from '~/repository/queries/project_path.query.graphql';
import refQuery from '~/repository/queries/ref.query.graphql';
import ProfileReadme from './components/profile_readme.vue';

export const initProfileReadme = () => {
  const el = document.getElementById('js-profile-readme');

  if (!el) return null;

  const { projectPath, ref, escapedRef, name, path, webPath } = el.dataset;
  const { cache } = apolloProvider.clients.defaultClient;

  // The preview component reads these from the Apollo cache (see repository/index.js).
  cache.writeQuery({ query: projectPathQuery, data: { projectPath } });
  cache.writeQuery({ query: refQuery, data: { ref, escapedRef } });

  return initVueApp({
    el,
    name: 'ProfileReadmeRoot',
    apolloProvider,
    provide: {
      // The profile README is always read from the project's default branch.
      refType: 'heads',
    },
    component: ProfileReadme,
    props: {
      blob: { name, path, webPath },
    },
  });
};
