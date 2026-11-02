import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import createRouter from '~/repository/router';
import initBlobShow from '~/blob/show/show_blob_bundle';
import { initEEBlobShow } from 'ee/blob/show/blob_show_bundle';

jest.mock('~/blob/show/show_blob_bundle', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('ee/vue_shared/components/code_owners/code_owners.vue', () => ({
  name: 'CodeOwners',
  // Mirrors the real component's declarations, so prop casting and defaults
  // behave here exactly as they do in the app.
  props: {
    projectPath: { type: String, required: true },
    filePath: { type: String, required: false, default: '' },
    branch: { type: String, required: false, default: '' },
    canViewBranchRules: { type: Boolean, required: false, default: false },
    branchRulesPath: { type: String, required: false, default: '' },
  },
  render(h) {
    return h('div');
  },
}));
jest.mock('jh_else_ce/repository/components/tree_content.vue', () => ({
  name: 'TreeContent',
  render: (h) => h('div'),
}));
jest.mock('~/repository/components/blob_content_viewer.vue', () => ({
  name: 'BlobContentViewer',
  render: (h) => h('div'),
}));
jest.mock('~/repository/utils/dom');

Vue.use(VueApollo);

describe('initEEBlobShow', () => {
  let apolloProvider;
  let app;

  // Haml renders a true data attribute with no value and omits it when false,
  // so the dataset yields '' or undefined here, never the string 'true'.
  const setHTML = ({ canViewBranchRules = true } = {}) => {
    document.body.innerHTML = `
      <div id="js-code-owners"
        data-blob-path="README.md"
        data-project-path="group/project"
        data-branch="main"
        ${canViewBranchRules ? 'data-can-view-branch-rules' : ''}
        data-branch-rules-path="/branch_rules"></div>`;
  };

  const codeOwnersProps = () => app.$children[0].$props;

  beforeEach(() => {
    apolloProvider = createMockApollo([]);
  });

  afterEach(() => {
    app?.$destroy();
    app = null;
    document.body.innerHTML = '';
  });

  it('does not mount when the element is absent', () => {
    document.body.innerHTML = '';
    initBlobShow.mockReturnValue({ router: null, apolloProvider });

    expect(initEEBlobShow()).toBe(null);
  });

  describe('when the blob app provides a router', () => {
    beforeEach(async () => {
      setHTML();
      const router = createRouter('group/project', 'main', 'Project');
      await router.push('/-/blob/main/lib/utils.js').catch(() => {});
      initBlobShow.mockReturnValue({ router, apolloProvider });

      app = initEEBlobShow();
    });

    it('takes the file path from the route rather than the dataset', () => {
      expect(codeOwnersProps().filePath).toBe('lib/utils.js');
    });

    it('reaches CodeOwners as true when the user can view branch rules', () => {
      expect(codeOwnersProps().canViewBranchRules).toBe(true);
    });
  });

  describe('when the blob app provides no router', () => {
    beforeEach(() => {
      setHTML();
      initBlobShow.mockReturnValue({ router: null, apolloProvider });

      app = initEEBlobShow();
    });

    it('falls back to the dataset path', () => {
      expect(codeOwnersProps().filePath).toBe('README.md');
    });

    it('still reaches CodeOwners as true', () => {
      expect(codeOwnersProps().canViewBranchRules).toBe(true);
    });
  });

  describe('when the user cannot view branch rules', () => {
    beforeEach(() => {
      setHTML({ canViewBranchRules: false });
      initBlobShow.mockReturnValue({ router: null, apolloProvider });

      app = initEEBlobShow();
    });

    it('reaches CodeOwners as false', () => {
      expect(codeOwnersProps().canViewBranchRules).toBe(false);
    });
  });
});
