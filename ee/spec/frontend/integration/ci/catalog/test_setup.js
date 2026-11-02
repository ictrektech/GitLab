import versionsFixture from 'test_fixtures/graphql/ci/catalog/integration/get_ci_catalog_resource_versions.query.graphql.json';
import setWindowLocation from 'helpers/set_window_location_helper';
import { getText, registerBootstrappedApp } from 'ee_jest/integration/helpers/test_helpers';
import { initCatalog } from '~/ci/catalog';
import { exploreCatalogIndexPath } from '~/lib/utils/path_helpers/explore';

const RESOURCE_WEB_PATH = versionsFixture.data.ciCatalogResource.webPath;

function mountCatalog(path) {
  setWindowLocation(`${exploreCatalogIndexPath()}${path}`);

  const el = document.createElement('div');
  el.id = 'js-ci-cd-catalog';
  Object.assign(el.dataset, {
    reportAbusePath: '/-/abuse_reports/add_category',
    legalDisclaimer: '',
  });
  document.body.appendChild(el);

  return registerBootstrappedApp(initCatalog());
}

export const mountCatalogList = () => mountCatalog('');

export function mountCatalogDetails({ query = '' } = {}) {
  return mountCatalog(`${RESOURCE_WEB_PATH}${query}`);
}

export const findTab = (name) =>
  [...document.querySelectorAll('[role="tab"]')].find((element) => getText(element) === name) ??
  null;

export const findEmptyState = () => document.querySelector('.gl-empty-state');

export const findReadme = () => document.querySelector('[role="tabpanel"].active .md');

export const findVersionOption = (name) =>
  [...document.querySelectorAll('[role="option"]')].find((element) =>
    getText(element).startsWith(name),
  ) ?? null;

export const findSelectedVersion = () =>
  document.querySelector('[role="option"][aria-selected="true"]');

export const findResourceItems = () =>
  document.querySelectorAll('[data-testid="catalog-resource-item"]');

export const findVersionBadge = () =>
  document.querySelector('[data-testid="current-version-badge"]');
