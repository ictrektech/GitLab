import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initTree from '~/repository';
import repositoryPathMixin from '~/repository/mixins/repository_path';
import CodeOwners from '../vue_shared/components/code_owners/code_owners.vue';

const initCodeOwnersApp = (router, apolloProvider, projectPath) => {
  const codeOwnersEl = document.querySelector('#js-code-owners');
  if (!codeOwnersEl) return null;

  const { branch, canViewBranchRules, branchRulesPath } = codeOwnersEl.dataset;
  return initVueApp({
    el: codeOwnersEl,
    name: 'RepositoryCodeOwnersRoot',
    router,
    apolloProvider,
    component: {
      name: 'RepositoryCodeOwnersApp',
      mixins: [repositoryPathMixin],
      render(h) {
        return h(CodeOwners, {
          props: {
            filePath: this.computedPath,
            projectPath,
            branch,
            canViewBranchRules,
            branchRulesPath,
          },
        });
      },
    },
  });
};

export default () => {
  const tree = initTree();
  if (!tree) return;

  const { router, apolloProvider, projectPath } = tree;

  initCodeOwnersApp(router, apolloProvider, projectPath);
};
