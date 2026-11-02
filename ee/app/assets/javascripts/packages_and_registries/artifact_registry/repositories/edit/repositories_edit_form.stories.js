import createMockApollo from 'helpers/mock_apollo_helper';
import {
  ORGANIZATION_GID,
  mockRepository,
  mockRepositoryPermissions,
  mockRepositoryResponse,
  mockUpdateRepositoryResponse,
  mockUpstreamRepositoriesResponse,
  mockUpstreamRepositoryCandidatePages,
  mockUpstreamRepositoryCandidatesResponse,
  mockWrittenRepository,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import { REPOSITORY_EDIT_ROUTE_NAME } from '../../constants';
import updateRepositoryMutation from '../../graphql/mutations/update_repository.mutation.graphql';
import getRepositoryQuery from '../../graphql/queries/get_repository.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from '../../graphql/queries/get_repository_upstream_repositories.query.graphql';
import getUpstreamRepositoryCandidatesQuery from '../../graphql/queries/get_upstream_repository_candidates.query.graphql';
import { createRouter } from '../../router';
import RepositoriesEditForm from './repositories_edit_form.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const prefillHandler = (repository) => () => Promise.resolve(mockRepositoryResponse(repository));

const updateHandler = ({ input }) =>
  Promise.resolve(mockUpdateRepositoryResponse({ repository: mockWrittenRepository(input) }));

const upstreamRepositoriesHandler = ({ name }) =>
  Promise.resolve(mockUpstreamRepositoriesResponse({ name }));

const candidatesHandler = () => {
  let index = 0;

  return () => {
    const pages = mockUpstreamRepositoryCandidatePages;
    const page = pages[Math.min(index, pages.length - 1)];
    index += 1;

    return Promise.resolve(mockUpstreamRepositoryCandidatesResponse(page));
  };
};

export default {
  component: RepositoriesEditForm,
  title: 'ee/packages_and_registries/artifact_registry/repositories/edit/repositories_edit_form',
};

const Template = (repositoryHandler) => () => {
  // The view reads the repository named in the route, so the story stands on the edit route
  // before it renders.
  const router = createRouter(BASE_PATH);
  router
    .push({ name: REPOSITORY_EDIT_ROUTE_NAME, params: { id: mockRepository.name } })
    .catch(() => {});

  return {
    components: { RepositoriesEditForm },
    router,
    apolloProvider: createMockApollo([
      [getRepositoryQuery, repositoryHandler],
      [getRepositoryUpstreamRepositoriesQuery, upstreamRepositoriesHandler],
      [getUpstreamRepositoryCandidatesQuery, candidatesHandler()],
      [updateRepositoryMutation, updateHandler],
    ]),
    provide: { organizationGid: ORGANIZATION_GID },
    template: '<repositories-edit-form />',
  };
};

export const Default = Template(
  prefillHandler({ ...mockWrittenRepository(), userPermissions: mockRepositoryPermissions() }),
);

export const Virtual = Template(
  prefillHandler({
    ...mockWrittenRepository({ kind: 'VIRTUAL' }),
    userPermissions: mockRepositoryPermissions(),
  }),
);

export const Loading = Template(() => new Promise(() => {}));

export const ServiceUnavailable = Template(() => Promise.reject(new Error('Unavailable')));

export const NotFound = Template(prefillHandler(null));
