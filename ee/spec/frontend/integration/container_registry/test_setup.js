import setWindowLocation from 'helpers/set_window_location_helper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import registryExplorer from '~/packages_and_registries/container_registry/explorer/index';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getText,
  registerBootstrappedApp,
  screen,
  setInputValue,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  waitForSetup,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findShownModal,
  findSortDirectionButton,
} from 'ee_jest/integration/helpers/registry_helpers';
import {
  getContainerRepositoriesDetails,
  getProjectContainerRepositories,
} from './fixture_variants';
import { resetContainerRegistryState } from './handlers';

export const PROJECT_FULL_PATH = 'registry-fixtures/registry-project';
export const GROUP_FULL_PATH = 'registry-group';

export const PROJECT_REGISTRY_PATH = `/${PROJECT_FULL_PATH}/container_registry`;
export const GROUP_REGISTRY_PATH = `/groups/${GROUP_FULL_PATH}/-/container_registries`;
export const PROJECT_SETTINGS_PATH = `/${PROJECT_FULL_PATH}/-/settings/packages_and_registries#container-registry-settings`;

const REGISTRY_HOST = 'registry.example.com:5000';

const SHARED_DATASET = {
  noContainersImage: '/assets/illustrations/status/status-nothing-md.svg',
  containersErrorImage: '/assets/illustrations/status/status-fail-md.svg',
  registryHostUrlWithPort: REGISTRY_HOST,
  isAdmin: 'false',
  gidPrefix: 'gid://gitlab/ContainerRepository/',
  connectionError: 'false',
  invalidPathError: 'false',
  userCalloutsPath: '/-/users/callouts',
  userCalloutId: 'unfinished_tag_cleanup_callout',
  isMetadataDatabaseEnabled: 'true',
  showUnfinishedTagCleanupCallout: 'false',
};

const PROJECT_DATASET = {
  ...SHARED_DATASET,
  endpoint: PROJECT_REGISTRY_PATH,
  expirationPolicy: JSON.stringify({ enabled: false }),
  repositoryUrl: `${REGISTRY_HOST}/${PROJECT_FULL_PATH}`,
  projectPath: PROJECT_FULL_PATH,
  showCleanupPolicyLink: 'false',
  cleanupPoliciesSettingsPath: `/${PROJECT_FULL_PATH}/-/settings/packages_and_registries/cleanup_image_tags`,
  showContainerRegistrySettings: 'false',
  settingsPath: PROJECT_SETTINGS_PATH,
  securityConfigurationPath: `/${PROJECT_FULL_PATH}/-/security/configuration`,
  vulnerabilityReportPath: `/${PROJECT_FULL_PATH}/-/security/vulnerability_report?tab=CONTAINER_REGISTRY`,
};

const GROUP_DATASET = {
  ...SHARED_DATASET,
  endpoint: GROUP_REGISTRY_PATH,
  isGroupPage: 'true',
  groupPath: GROUP_FULL_PATH,
};

export const listedImageName = ({ name, project }) =>
  [project.path.toLowerCase(), name].filter(Boolean).join('/');

export const manyImageNames =
  getProjectContainerRepositories.MANY.data.project.containerRepositories.nodes.map(
    listedImageName,
  );

export const detailsRoute = (repository) => `/${getIdFromGraphQLId(repository.id)}`;

export const useRepositoriesVariant = (variant) => {
  setQueryVariant(getProjectContainerRepositories)[variant]();
  setQueryVariant(getContainerRepositoriesDetails)[variant]();
};

function mountRegistry(dataset, { route = '', ...overrides }) {
  resetContainerRegistryState();
  setWindowLocation(`${dataset.endpoint}${route}`);

  const breadcrumbEl = document.createElement('div');
  breadcrumbEl.id = 'js-injected-page-breadcrumbs';
  document.body.appendChild(breadcrumbEl);

  const el = document.createElement('div');
  el.id = 'js-container-registry';
  Object.assign(el.dataset, dataset, overrides);
  document.body.appendChild(el);

  const explorer = registryExplorer();
  registerBootstrappedApp(explorer.attachBreadcrumb());

  return registerBootstrappedApp(explorer.attachMainComponent());
}

export const mountProjectRegistry = (options = {}) => mountRegistry(PROJECT_DATASET, options);

export const mountGroupRegistry = (options = {}) => mountRegistry(GROUP_DATASET, options);

export const findImageLinks = () => screen.queryAllByTestId('details-link');

export const findImageLinkTexts = () => findImageLinks().map(getText);

export const waitForImages = (names) =>
  waitForSetup(() => {
    expect(findImageLinkTexts()).toEqual(names);
  });

export const findTagNames = () => screen.queryAllByTestId('name').map(getText);

export const waitForTags = (count) =>
  waitForSetup(() => {
    expect(findTagNames()).toHaveLength(count);
  });

export const findBodyText = () => getText(document.body);

export const findBreadcrumb = () => document.querySelector('.gl-breadcrumbs');

export const findImageTitle = () => screen.queryByTestId('title');

export const findTagsCount = () => screen.queryByTestId('tags-count');

export const waitForTagsCount = (text) =>
  waitForAssertion(() => {
    expect(getText(findTagsCount())).toBe(text);
  });

export const findNextPageButton = () => screen.queryByTestId('nextButton');

export const openImageDetails = (name) =>
  waitAndClick(() => findImageLinks().find((link) => getText(link) === name) ?? null);

export const goToNextPage = () => waitAndClick(findNextPageButton);

export const toggleSortDirection = () => waitAndClick(findSortDirectionButton);

const confirmModal = async (title) => {
  const modal = await waitForElement(findShownModal);
  expect(getText(modal.querySelector('.modal-title'))).toBe(title);
  return modal;
};

export const deleteImageFromList = async (repository) => {
  const row = findImageLinks()
    .find((link) => getText(link) === listedImageName(repository))
    .closest('li');
  within(row).getByRole('button', { name: 'Remove repository' }).click();

  const modal = await confirmModal('Delete image repository?');
  setInputValue(modal.querySelector('input'), repository.name);

  await waitAndClick(() => {
    const button = within(modal).getByRole('button', { name: 'Delete' });
    return button.disabled ? null : button;
  });
};

export const deleteFirstTag = async () => {
  const [firstRow] = screen.queryAllByTestId('additional-actions');
  within(firstRow).getByRole('button', { name: 'More actions' }).click();
  await waitAndClick(() => firstRow.querySelector('[data-testid="single-delete-button"]'));

  const modal = await confirmModal('Remove tag');
  within(modal).getByRole('button', { name: 'Delete' }).click();
};

export const waitForBodyText = (text) =>
  waitForAssertion(() => {
    expect(findBodyText()).toContain(text);
  });
