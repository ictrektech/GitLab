import setWindowLocation from 'helpers/set_window_location_helper';
import { TEST_HOST } from 'helpers/test_constants';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import initPackageRegistry from '~/packages_and_registries/package_registry/index';
import {
  getText,
  registerBootstrappedApp,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { findShownModal } from 'ee_jest/integration/helpers/registry_helpers';
import { GROUP_FULL_PATH, PROJECT_FULL_PATH, groupId, resetPackageRegistryState } from './handlers';

export const PROJECT_PACKAGES_PATH = `/${PROJECT_FULL_PATH}/-/packages`;
export const GROUP_PACKAGES_PATH = `/groups/${GROUP_FULL_PATH}/-/packages`;

const EMPTY_LIST_ILLUSTRATION = '/assets/illustrations/empty-state/empty-package-md.svg';
const NPM_INSTANCE_URL = `${TEST_HOST}/api/v4/packages/npm`;

const PROJECT_DATASET = {
  endpoint: PROJECT_PACKAGES_PATH,
  fullPath: PROJECT_FULL_PATH,
  pageType: 'projects',
  emptyListIllustration: EMPTY_LIST_ILLUSTRATION,
  npmInstanceUrl: NPM_INSTANCE_URL,
  npmGroupUrl: `${TEST_HOST}/api/v4/groups/-/packages/npm`,
  projectListUrl: PROJECT_PACKAGES_PATH,
  groupListUrl: '',
  settingsPath: `/${PROJECT_FULL_PATH}/-/settings/packages_and_registries#package-registry-settings`,
  canDeletePackages: 'true',
};

const GROUP_DATASET = {
  endpoint: GROUP_PACKAGES_PATH,
  fullPath: GROUP_FULL_PATH,
  pageType: 'groups',
  emptyListIllustration: EMPTY_LIST_ILLUSTRATION,
  npmInstanceUrl: NPM_INSTANCE_URL,
  npmGroupUrl: `${TEST_HOST}/api/v4/groups/${getIdFromGraphQLId(groupId)}/-/packages/npm`,
  projectListUrl: '',
  groupListUrl: GROUP_PACKAGES_PATH,
  settingsPath: '',
  canDeletePackages: 'true',
};

const PERSISTED_STORAGE_KEYS = [
  'package_registry_list_sorting',
  'group_package_registry_list_sorting',
  'packages_page_size',
];

export const packageDetailsRoute = (packageEntity) => `/${getIdFromGraphQLId(packageEntity.id)}`;

function mountPackagesApp(dataset, route) {
  resetPackageRegistryState();
  PERSISTED_STORAGE_KEYS.forEach((key) => window.localStorage.removeItem(key));
  setWindowLocation(`${dataset.endpoint}${route}`);

  const el = document.createElement('div');
  el.id = 'js-vue-packages-list';
  Object.assign(el.dataset, dataset);
  document.body.appendChild(el);

  return registerBootstrappedApp(initPackageRegistry().attachMainComponent());
}

export const mountProjectPackagesApp = ({ route = '' } = {}) =>
  mountPackagesApp(PROJECT_DATASET, route);

export const mountGroupPackagesApp = ({ route = '' } = {}) =>
  mountPackagesApp(GROUP_DATASET, route);

export const findPackageRows = () => screen.queryAllByTestId('package-row');

export const findPackageRowTexts = () => findPackageRows().map(getText);

export const waitForPackageRows = (count) =>
  waitForAssertion(() => {
    expect(findPackageRows()).toHaveLength(count);
  });

export const findHeading = () => screen.queryByTestId('page-heading');

export const findFilteredSearchInput = () => screen.queryByTestId('filtered-search-term-input');

export const findActiveFilteredSearchInput = () =>
  screen.queryByTestId('filtered-search-token-segment-input');

export const findSuggestion = (text) =>
  [...document.querySelectorAll('.gl-filtered-search-suggestion-list .dropdown-item')].find(
    (element) => getText(element) === text,
  ) ?? null;

export const selectSuggestion = async (text) => {
  const suggestion = await waitForElement(() => findSuggestion(text));

  ['mousedown', 'mouseup', 'click'].forEach((type) => {
    suggestion.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true }));
  });
};

export const filterByType = async (typeText) => {
  const idleInput = await waitForElement(findFilteredSearchInput);
  idleInput.focus();
  idleInput.click();
  await waitForElement(findActiveFilteredSearchInput);

  await selectSuggestion('Type');
  await selectSuggestion(typeText);
  await waitAndClick(() => screen.queryByTestId('search-button'));
};

export const currentQueryParams = () =>
  Object.fromEntries(new URLSearchParams(window.location.search));

export const findOtherVersionsBadge = () => screen.queryByTestId('other-versions-badge');

export const findOtherVersionsTab = () => findOtherVersionsBadge()?.closest('[role="tab"]') ?? null;

export const findOtherVersionsPanel = () => {
  const panelId = findOtherVersionsTab()?.getAttribute('aria-controls');
  return panelId ? document.getElementById(panelId) : null;
};

const deleteFromActionsDropdown = async (container) => {
  container.querySelector('[data-testid="delete-dropdown"] button').click();
  await waitAndClick(
    () =>
      container
        .querySelector('[data-testid="action-delete"]')
        ?.closest('.gl-new-dropdown-item')
        ?.querySelector('.gl-new-dropdown-item-content') ?? null,
  );

  const modal = await waitForElement(findShownModal);
  expect(getText(modal)).toContain('Delete package version');
  within(modal).getByRole('button', { name: 'Permanently delete' }).click();
};

export const deletePackageFromRow = (row) => deleteFromActionsDropdown(row);

export const deleteFirstOtherVersion = () => deleteFromActionsDropdown(findOtherVersionsPanel());
