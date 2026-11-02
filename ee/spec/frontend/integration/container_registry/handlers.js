import { join } from 'node:path';
import { cloneDeep } from 'lodash-es';
import { HttpResponse } from 'msw';
import {
  createFixturePaginator,
  loadFixturesMap,
  matchFixture,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import './fixture_variants/get_project_container_repositories';
import './fixture_variants/get_container_repositories_details';
import './fixture_variants/get_container_repository_tags';
import './fixture_variants/get_container_repository_metadata';

const FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/packages_and_registries/container_registry/integration/',
);
const fixtures = loadFixturesMap(FIXTURES_PATH);

const REPOSITORY_SCENARIOS = ['Project', 'Nameless', 'Many', 'Group', 'SameName'];

const repositoryOf = (scenario) =>
  fixtures[`repositoryDetails${scenario}`].data.containerRepository;

export const projectRepository = repositoryOf('Project');
export const namelessRepository = repositoryOf('Nameless');
export const manyRepository = repositoryOf('Many');
export const groupRepository = repositoryOf('Group');
export const sameNameRepository = repositoryOf('SameName');

const tagsOf = (fixture) => fixture.data.containerRepository.tags;

export const manyTagsTotal = fixtures.repositoryTagsProjectMany.data.containerRepository.tagsCount;
export const manyTags = tagsOf(fixtures.repositoryTagsProjectMany).nodes;
export const manyTagsNameDesc = tagsOf(fixtures.repositoryTagsProjectManyNameDesc).nodes;
export const manyTagsNameAsc = tagsOf(fixtures.repositoryTagsProjectManyNameAsc).nodes;
export const manyTagsSecondPage = () => tagsOf(fixtures.repositoryTagsProjectManyPage2).nodes;

const DEFAULT_TAGS_SORT = 'PUBLISHED_AT_DESC';

const MANY_TAGS_BY_NAME_SORT = {
  NAME_DESC: fixtures.repositoryTagsProjectManyNameDesc,
  NAME_ASC: fixtures.repositoryTagsProjectManyNameAsc,
};

const paginateRepositories = createFixturePaginator({ lookupKey: 'containerRepositories' });

const repositoryIdTable = (prefix, scenarios = REPOSITORY_SCENARIOS) =>
  scenarios.map((scenario) => {
    const fixture = fixtures[`${prefix}${scenario}`];

    return {
      matches: ({ id, after }) => id === fixture.data.containerRepository.id && !after,
      fixture: () => fixture,
    };
  });

const REPOSITORY_ID_TABLES = {
  getContainerRepositoryDetails: repositoryIdTable('repositoryDetails'),
  getContainerRepositoryMetadata: [
    {
      matches: ({ id }) => id === projectRepository.id,
      fixture: () =>
        getActiveVariant('getContainerRepositoryMetadata') ?? fixtures.repositoryMetadataProject,
    },
    ...repositoryIdTable(
      'repositoryMetadata',
      REPOSITORY_SCENARIOS.filter((scenario) => scenario !== 'Project'),
    ),
  ],
  getContainerRepositoryTags: [
    {
      matches: ({ id, sort, after }) =>
        id === projectRepository.id &&
        sort === 'NAME_ASC' &&
        after === tagsOf(fixtures.repositoryTagsProjectManyNameAsc).pageInfo.endCursor,
      fixture: () => fixtures.repositoryTagsProjectManyPage2,
    },
    ...Object.entries(MANY_TAGS_BY_NAME_SORT).map(([nameSort, fixture]) => ({
      matches: ({ id, sort, after }) => id === projectRepository.id && sort === nameSort && !after,
      fixture: () => fixture,
    })),
    {
      matches: ({ id, sort, after }) =>
        id === projectRepository.id && sort === DEFAULT_TAGS_SORT && !after,
      fixture: () =>
        getActiveVariant('getContainerRepositoryTags') ?? fixtures.repositoryTagsProject,
    },
    ...repositoryIdTable(
      'repositoryTags',
      REPOSITORY_SCENARIOS.filter((scenario) => scenario !== 'Project'),
    ),
  ],
};

const matchTable = (operationName, variables) =>
  matchFixture(variables, REPOSITORY_ID_TABLES[operationName], operationName).fixture();

let deletedTagNames = new Map();

export function resetContainerRegistryState() {
  deletedTagNames = new Map();
}

const REPOSITORIES_BASES = {
  getProjectContainerRepositories: {
    project: fixtures.projectRepositories,
    group: fixtures.groupRepositories,
  },
  getContainerRepositoriesDetails: {
    project: fixtures.projectRepositoriesDetails,
    group: fixtures.groupRepositoriesDetails,
  },
};

function repositoriesResponse(operationName, variables) {
  const { project, group } = REPOSITORIES_BASES[operationName];

  return paginateRepositories(
    getActiveVariant(operationName) ?? (variables.isGroupPage ? group : project),
    variables,
  );
}

function tagsResponse(variables) {
  const response = cloneDeep(matchTable('getContainerRepositoryTags', variables));
  const deleted = deletedTagNames.get(variables.id);

  if (deleted) {
    const { containerRepository } = response.data;

    containerRepository.tags.nodes = containerRepository.tags.nodes.filter(
      ({ name }) => !deleted.has(name),
    );
    containerRepository.tagsCount -= deleted.size;
  }

  return response;
}

function destroyTagsResponse({ id, tagNames }) {
  deletedTagNames.set(id, new Set([...(deletedTagNames.get(id) ?? []), ...tagNames]));
  return fixtures.destroyContainerRepositoryTags;
}

const OPERATION_HANDLERS = {
  getProjectContainerRepositories: ({ variables }) =>
    repositoriesResponse('getProjectContainerRepositories', variables),
  getContainerRepositoriesDetails: ({ variables }) =>
    repositoriesResponse('getContainerRepositoriesDetails', variables),
  getContainerRepositoryDetails: ({ variables }) =>
    matchTable('getContainerRepositoryDetails', variables),
  getContainerRepositoryMetadata: ({ variables }) =>
    matchTable('getContainerRepositoryMetadata', variables),
  getContainerRepositoryTags: ({ variables }) => tagsResponse(variables),
  getProjectContainerScanning: () => fixtures.getProjectContainerScanning,
  destroyContainerRepositoryTags: ({ variables }) => destroyTagsResponse(variables),
  destroyContainerRepository: () => fixtures.destroyContainerRepository,
};

export function handleContainerRegistryOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  return HttpResponse.json(handler({ variables }));
}

export const containerRegistryRestEndpoints = [
  {
    name: 'restSecurityConfiguration',
    method: 'get',
    path: /\/-\/security\/configuration$/,
    response: fixtures.restSecurityConfiguration,
  },
];
