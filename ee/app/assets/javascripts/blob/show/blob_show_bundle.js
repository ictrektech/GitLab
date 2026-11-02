import Vue from 'vue';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initBlobShow from '~/blob/show/show_blob_bundle';
import repositoryPathMixin from '~/repository/mixins/repository_path';
import CodeOwners from 'ee/vue_shared/components/code_owners/code_owners.vue';

export function initEEBlobShow() {
  const { router, apolloProvider } = initBlobShow();

  const codeOwnersEl = document.querySelector('#js-code-owners');
  if (!codeOwnersEl) return null;

  const { blobPath, projectPath, branch, canViewBranchRules, branchRulesPath } =
    codeOwnersEl.dataset;

  const sharedProps = {
    projectPath,
    branch,
    canViewBranchRules,
    branchRulesPath,
  };

  // The expanded view has no blob router, so the path cannot change without a
  // reload and the dataset value is the only one available.
  if (!router) {
    return initVueApp({
      el: codeOwnersEl,
      name: 'CodeOwnersRoot',
      apolloProvider,
      component: CodeOwners,
      props: { ...sharedProps, filePath: blobPath },
    });
  }

  return new Vue({
    el: codeOwnersEl,
    name: 'CodeOwnersRoot',
    router,
    apolloProvider,
    mixins: [repositoryPathMixin],
    render(h) {
      return h(CodeOwners, {
        props: { ...sharedProps, filePath: this.computedPath },
      });
    },
  });
}
