import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { pinia } from '~/pinia/instance';
import apolloProvider from '~/repository/graphql';
import createRouter from '~/repository/router';
import HeaderArea from '~/repository/components/header_area.vue';
import projectPathQuery from '~/repository/queries/project_path.query.graphql';
import projectShortPathQuery from '~/repository/queries/project_short_path.query.graphql';
import refsQuery from '~/repository/queries/ref.query.graphql';
import {
  assignRouter,
  fullMount,
  screen,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { setFeatureFlags, setLicensedFeatures } from 'ee_jest/integration/helpers/setup_utils';
import { resetPathLockState } from './handlers';

Vue.use(VueApollo);

// Does not need to match the recorded project's path: the handlers serve
// fixtures regardless of request variables, and Apollo normalizes by id.
export const PROJECT_FULL_PATH = 'gitlab-org/gitlab-test';
export const DEFAULT_BRANCH = 'master';

const PROJECT_BASE = `/${PROJECT_FULL_PATH}`;

// Mirrors app/assets/javascripts/repository/init_header_app.js
export async function mountHeaderArea({
  route = '/',
  currentRef = DEFAULT_BRANCH,
  glFeatures = {},
  glLicensedFeatures = {},
  downloadLinks = [],
  showWebIdeButton = true,
} = {}) {
  resetPathLockState();

  setFeatureFlags({ ...glFeatures });
  setLicensedFeatures({ fileLocks: true, ...glLicensedFeatures });

  await apolloProvider.defaultClient.cache.reset();

  // Client-only queries the page bootstrap seeds before mounting.
  apolloProvider.defaultClient.cache.writeQuery({
    query: projectPathQuery,
    data: { projectPath: PROJECT_FULL_PATH },
  });
  apolloProvider.defaultClient.cache.writeQuery({
    query: projectShortPathQuery,
    data: { projectShortPath: 'gitlab-test' },
  });
  apolloProvider.defaultClient.cache.writeQuery({
    query: refsQuery,
    data: { ref: currentRef, escapedRef: currentRef },
  });

  // Positional-args factory, and tests start at different routes/refs, so the
  // router is created per mount (its route patterns embed the ref).
  const router = assignRouter(() => createRouter(PROJECT_FULL_PATH, currentRef, 'GitLab Test'), {
    routerLocation: `${PROJECT_BASE}${route}`,
  });

  return fullMount(HeaderArea, {
    router,
    apolloProvider,
    pinia,
    // VTU v1 stubs <transition> by default, which skips the JS hooks GlModal's
    // BModal relies on to leave its `isTransitioning` state — the second
    // open of the same modal then renders a disabled primary button. Real
    // transitions complete instantly in jsdom, so unstub them.
    stubs: { transition: false, 'transition-group': false },
    propsData: {
      projectPath: PROJECT_FULL_PATH,
      refType: null,
      currentRef,
      projectId: 'gid://gitlab/Project/1',
    },
    provide: {
      canCollaborate: true,
      canEditTree: true,
      canPushCode: true,
      canPushToBranch: true,
      originalBranch: currentRef,
      selectedBranch: currentRef,
      newBranchPath: `${PROJECT_BASE}/-/branches/new`,
      newTagPath: `${PROJECT_BASE}/-/tags/new`,
      newBlobPath: `${PROJECT_BASE}/-/new/${DEFAULT_BRANCH}`,
      forkNewBlobPath: '',
      forkNewDirectoryPath: '',
      forkUploadBlobPath: '',
      uploadPath: `${PROJECT_BASE}/-/create/${DEFAULT_BRANCH}`,
      newDirPath: `${PROJECT_BASE}/-/create_dir/${DEFAULT_BRANCH}`,
      projectRootPath: PROJECT_BASE,
      comparePath: `${PROJECT_BASE}/-/compare`,
      isReadmeView: false,
      isFork: false,
      needsToFork: false,
      isGitpodEnabledForUser: false,
      isBlob: route.includes('/-/blob/'),
      showEditButton: true,
      showWebIdeButton,
      isGitpodEnabledForInstance: false,
      showPipelineEditorButton: false,
      webIdeUrl: `/-/ide/project${PROJECT_BASE}`,
      editUrl: '',
      pipelineEditorUrl: '',
      gitpodUrl: '',
      userPreferencesGitpodPath: '',
      userProfileEnableGitpodPath: '',
      httpUrl: 'http://localhost/gitlab-org/gitlab-test.git',
      xcodeUrl: '',
      sshUrl: 'ssh://git@localhost/gitlab-org/gitlab-test.git',
      kerberosUrl: '',
      downloadLinks,
      downloadArtifacts: [],
      isBinary: false,
      rootRef: DEFAULT_BRANCH,
      showNoSshKeyMessage: false,
      userSettingsSshKeysPath: '/-/user_settings/ssh_keys',
      customCodeDropdownClients: [],
      newWorkspacePath: '/-/remote_development/workspaces/new',
      organizationId: '1',
    },
  });
}

export const mountTreeHeaderArea = (options = {}) =>
  mountHeaderArea({ route: `/-/tree/${DEFAULT_BRANCH}/encoding`, ...options });

export const mountBlobHeaderArea = ({ currentRef = DEFAULT_BRANCH, ...options } = {}) =>
  mountHeaderArea({ route: `/-/blob/${currentRef}/VERSION`, currentRef, ...options });

export const findCodeDropdownToggle = () =>
  document.querySelector('[data-testid="code-dropdown"] button');

const findDropdownGroupByLabel = (label) => screen.queryByText(label)?.closest('li') ?? null;

export const findDownloadSourceCodeGroup = () => findDropdownGroupByLabel('Download source code');

export const findDownloadDirectoryGroup = () => findDropdownGroupByLabel('Download directory');

export const findSshCloneItem = () => document.querySelector('[data-testid="copy-ssh-url-button"]');

export const findWebIdeMenuItem = () => screen.queryByTestId('webide-menu-item');

export const findLockButton = () => screen.queryByTestId('lock-button');

export const findLockDisclosureToggle = () => screen.queryByTestId('lock-disclosure-toggle');

// Open the lock disclosure via its custom-toggle wrapper, which carries the
// dropdown's click listener. Under Vue 3 + jsdom a click on the inner button
// does not reach the wrapper, so clicking the button only appears to work in
// jsdom because the panel content pre-renders.
export const clickLockDisclosureToggle = async () => {
  const toggle = await waitForElement(findLockDisclosureToggle);
  toggle.closest('[data-testid="base-dropdown-toggle"]').click();
};

export const findLockDisclosureHeader = () => screen.queryByTestId('lock-disclosure-header');

export const findUnlockButton = () => screen.queryByTestId('unlock-button');

export const findNoPermissionMessage = () => screen.queryByTestId('no-permission-message');

export const findRelatedLockAlert = () => screen.queryByTestId('related-lock-alert');

export const findViewLockedPathButton = () => screen.queryByTestId('view-locked-path-button');

export const findLockUserCard = () => screen.queryByTestId('lock-user-card');

export const findLockUserLink = () => screen.queryByTestId('lock-user-link');

// GitLab UI stamps this testid on the disclosure's toggle button. Null guard
// because the finder is polled before the menu renders and within(null) throws.
export const findBlobOverflowMenuToggle = () => {
  const menu = screen.queryByTestId('blob-overflow-menu');
  return menu ? within(menu).queryByTestId('base-dropdown-toggle') : null;
};

export const findReplaceItem = () => screen.queryByTestId('replace');

export const findDeleteItem = () => screen.queryByTestId('delete');

export const findPermalinkItem = () => screen.queryByTestId('permalink');

// The Edit dropdown (web_ide_link.vue). Its open panel is portaled out of the
// dropdown root, so items are scoped through the toggle's aria-controls id
// instead of the component element — the Code dropdown also renders a
// "webide-menu-item", so unscoped queries could match the wrong menu.
export const findEditDropdown = () => screen.queryByTestId('action-dropdown');

export const findEditDropdownToggle = () => {
  const dropdown = findEditDropdown();
  return dropdown ? within(dropdown).queryByTestId('base-dropdown-toggle') : null;
};

const findEditDropdownPanel = () => {
  const toggle = findEditDropdownToggle();
  return toggle ? document.getElementById(toggle.getAttribute('aria-controls')) : null;
};

// Names are regexes: the accessible name also includes the secondary text and shortcut.
const findEditDropdownAction = (role, name) => {
  const panel = findEditDropdownPanel();
  return panel ? within(panel).queryByRole(role, { name }) : null;
};

export const findSingleFileEditorItem = () => findEditDropdownAction('link', /Edit single file/);

export const findWebIdeEditItem = () => findEditDropdownAction('button', /Web IDE/);

// The fork suggestion modal (fork_suggestion_modal.vue); its "message" and
// "fork" testids are generic, so scope the queries to the modal element.
const FORK_SUGGESTION_MODAL_SELECTOR = '#fork-suggestion-modal';

export const findForkSuggestionMessage = () =>
  document.querySelector(`${FORK_SUGGESTION_MODAL_SELECTOR} [data-testid="message"]`);

export const findForkSuggestionForkButton = () =>
  document.querySelector(`${FORK_SUGGESTION_MODAL_SELECTOR} [data-testid="fork"]`);

export const findForkSuggestionCancelButton = () =>
  document.querySelector(`${FORK_SUGGESTION_MODAL_SELECTOR} [data-testid="cancel"]`);
