import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { camelCase, cloneDeep, upperFirst } from 'lodash-es';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { loadFixturesMap, matchFixture } from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_packages';
import './fixture_variants/get_packages_count';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/packages_and_registries/package_registry/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const PROJECT_FULL_PATH = 'packages-owner/registry-project';
export const GROUP_FULL_PATH = 'packages-group';
export const GROUP_PROJECT_ZZZ_FULL_PATH = `${GROUP_FULL_PATH}/project-zzz`;

export const projectNpmPackage = fixtures.getPackageDetailsProjectNpm.data.package;
export const projectMavenPackage = fixtures.getPackageDetailsProjectMaven.data.package;
export const groupNpmPackage = fixtures.getPackageDetailsGroupNpm.data.package;
export const groupMavenPackage = fixtures.getPackageDetailsGroupMaven.data.package;
export const projectNewestNpmPackage = fixtures.getPackageDetailsProjectNpmNewest.data.package;
export const groupNewestNpmPackage = fixtures.getPackageDetailsGroupNpmNewest.data.package;

export const groupId = fixtures.getPackageErrorsCountGroup.data.group.id;

const PROJECT_SORTS = [
  'CREATED_DESC',
  'CREATED_ASC',
  'NAME_DESC',
  'NAME_ASC',
  'VERSION_DESC',
  'VERSION_ASC',
  'TYPE_DESC',
  'TYPE_ASC',
];
const GROUP_SORTS = [...PROJECT_SORTS, 'PROJECT_PATH_DESC', 'PROJECT_PATH_ASC'];
const DEFAULT_SORT = 'CREATED_DESC';

const PAGE_SCOPES = [
  {
    isGroupPage: false,
    fullPath: PROJECT_FULL_PATH,
    sortVariable: 'sort',
    sorts: PROJECT_SORTS,
    listPrefix: 'getPackages',
    countPrefix: 'getPackagesCount',
    root: 'project',
  },
  {
    isGroupPage: true,
    fullPath: GROUP_FULL_PATH,
    sortVariable: 'groupSort',
    sorts: GROUP_SORTS,
    listPrefix: 'getPackagesGroup',
    countPrefix: 'getPackagesCountGroup',
    root: 'group',
  },
];

const scopeMatches = (scope, { isGroupPage, fullPath }) =>
  isGroupPage === scope.isGroupPage && fullPath === scope.fullPath;

const hasUnrecordedFilters = ({ packageName, packageVersion, packageStatus, after, before }) =>
  Boolean(packageName || packageVersion || packageStatus || after || before);

const packagesListTable = PAGE_SCOPES.flatMap((scope) => [
  ...scope.sorts.map((sort) => ({
    matches: (variables) =>
      scopeMatches(scope, variables) &&
      variables[scope.sortVariable] === sort &&
      !variables.packageType &&
      !hasUnrecordedFilters(variables),
    fixture: () => fixtures[`${scope.listPrefix}${upperFirst(camelCase(sort))}`],
  })),
  {
    matches: (variables) =>
      scopeMatches(scope, variables) &&
      variables[scope.sortVariable] === DEFAULT_SORT &&
      variables.packageType === 'NPM' &&
      !hasUnrecordedFilters(variables),
    fixture: () => fixtures[`${scope.listPrefix}TypeNpm`],
  },
]);

const packagesCountTable = PAGE_SCOPES.flatMap((scope) => [
  {
    matches: (variables) =>
      scopeMatches(scope, variables) && !variables.packageType && !hasUnrecordedFilters(variables),
    fixture: () => fixtures[scope.countPrefix],
  },
  {
    matches: (variables) =>
      scopeMatches(scope, variables) &&
      variables.packageType === 'NPM' &&
      !hasUnrecordedFilters(variables),
    fixture: () => fixtures[`${scope.countPrefix}TypeNpm`],
  },
]);

const errorsCountTable = PAGE_SCOPES.map((scope) => ({
  matches: (variables) => scopeMatches(scope, variables),
  fixture: () =>
    scope.isGroupPage ? fixtures.getPackageErrorsCountGroup : fixtures.getPackageErrorsCount,
}));

const groupSettingsTable = [
  {
    matches: ({ fullPath, isGroupPage }) => fullPath === PROJECT_FULL_PATH && !isGroupPage,
    fixture: () => fixtures.getGroupPackageSettings,
  },
  {
    matches: ({ fullPath, isGroupPage }) => fullPath === GROUP_FULL_PATH && isGroupPage,
    fixture: () => fixtures.getGroupPackageSettingsGroup,
  },
  {
    matches: ({ fullPath, isGroupPage }) =>
      fullPath === GROUP_PROJECT_ZZZ_FULL_PATH && !isGroupPage,
    fixture: () => fixtures.getGroupPackageSettingsGroupProjectZzz,
  },
];

const packageIdTable = (operationName) =>
  Object.entries(fixtures)
    .filter(([key]) => key.startsWith(operationName))
    .map(([, fixture]) => ({
      matches: ({ id }) => getIdFromGraphQLId(id) === getIdFromGraphQLId(fixture.data.package.id),
      fixture: () => fixture,
    }));

const PACKAGE_ID_TABLES = Object.fromEntries(
  ['getPackageDetails', 'getPackagePipelines', 'getPackageFiles', 'getPackageVersions'].map(
    (operationName) => [operationName, packageIdTable(operationName)],
  ),
);

const matchTable = (operationName, variables, table) =>
  matchFixture(variables, table, operationName).fixture();

let deletedPackageIds = new Set();

export function resetPackageRegistryState() {
  deletedPackageIds = new Set();
}

function removeDeletedNodes(connection) {
  const nodes = connection.nodes.filter(({ id }) => !deletedPackageIds.has(getIdFromGraphQLId(id)));
  const removedCount = connection.nodes.length - nodes.length;

  Object.assign(connection, { nodes });
  if ('count' in connection) {
    Object.assign(connection, { count: connection.count - removedCount });
  }

  return removedCount;
}

function packagesListResponse(variables) {
  const response = cloneDeep(matchTable('getPackages', variables, packagesListTable));
  const scope = PAGE_SCOPES.find((candidate) => scopeMatches(candidate, variables));

  removeDeletedNodes(response.data[scope.root].packages);
  return response;
}

function packagesCountResponse(variables) {
  const response = cloneDeep(matchTable('getPackagesCount', variables, packagesCountTable));
  const scope = PAGE_SCOPES.find((candidate) => scopeMatches(candidate, variables));
  const list = cloneDeep(
    matchTable(
      'getPackages',
      { ...variables, [scope.sortVariable]: DEFAULT_SORT },
      packagesListTable,
    ),
  );

  response.data[scope.root].packages.count -= removeDeletedNodes(list.data[scope.root].packages);
  return response;
}

function packageVersionsResponse(variables) {
  const response = cloneDeep(
    matchTable('getPackageVersions', variables, PACKAGE_ID_TABLES.getPackageVersions),
  );

  removeDeletedNodes(response.data.package.versions);
  return response;
}

function destroyPackagesResponse({ ids }) {
  ids.forEach((id) => deletedPackageIds.add(getIdFromGraphQLId(id)));
  return fixtures.destroyPackages;
}

const OPERATION_HANDLERS = {
  getPackages: ({ variables }) =>
    getActiveVariant('getPackages') ?? packagesListResponse(variables),
  getPackagesCount: ({ variables }) =>
    getActiveVariant('getPackagesCount') ?? packagesCountResponse(variables),
  getPackageErrorsCount: ({ variables }) =>
    matchTable('getPackageErrorsCount', variables, errorsCountTable),
  getGroupPackageSettings: ({ variables }) =>
    matchTable('getGroupPackageSettings', variables, groupSettingsTable),
  getPackageDetails: ({ variables }) =>
    matchTable('getPackageDetails', variables, PACKAGE_ID_TABLES.getPackageDetails),
  getPackagePipelines: ({ variables }) =>
    matchTable('getPackagePipelines', variables, PACKAGE_ID_TABLES.getPackagePipelines),
  getPackageFiles: ({ variables }) =>
    matchTable('getPackageFiles', variables, PACKAGE_ID_TABLES.getPackageFiles),
  getPackageVersions: ({ variables }) => packageVersionsResponse(variables),
  destroyPackages: ({ variables }) => destroyPackagesResponse(variables),
};

export function handlePackageRegistryOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const packageRegistryRestEndpoints = [];
