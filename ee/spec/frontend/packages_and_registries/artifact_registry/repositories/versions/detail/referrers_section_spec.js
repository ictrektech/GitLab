import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { observable, resetObservable } from '~/lib/utils/observable';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import ReferrersSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_section.vue';
import ReferrersTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_table.vue';
import {
  ARTIFACT_ID_FOR,
  FIRST_PAGE_END_CURSOR,
  MANIFEST_DIGEST,
  MANIFEST_PARENT_DIGEST,
  ORGANIZATION_GID,
  SECOND_PAGE_START_CURSOR,
  mockManifestReferrer,
  mockManifestReferrers,
  mockManifestReferrersRepository,
  mockRepository,
  mockRepositoryResponse,
} from '../../../mock_data';

Vue.use(VueApollo);

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const ROUTE_STATE_KEY = 'artifact_registry_referrers_section_spec_route';

const REFERRERS_PATH = `/${mockRepository.name}/${ARTIFACT_ID}/manifests/${MANIFEST_DIGEST}`;

const IDENTITY_VARIABLES = {
  organizationId: ORGANIZATION_GID,
  name: mockRepository.name,
  artifactId: ARTIFACT_ID,
  digest: MANIFEST_DIGEST,
};

const successHandler = (repository = mockManifestReferrersRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

describe('ArtifactRegistryReferrersSection', () => {
  let wrapper;
  let handler;

  const push = jest.fn();

  let route;

  const createComponent = ({ requestHandler = successHandler(), query = {}, ...props } = {}) => {
    handler = requestHandler;
    resetObservable(ROUTE_STATE_KEY);
    route = observable(ROUTE_STATE_KEY, { path: REFERRERS_PATH, query });

    wrapper = shallowMountExtended(ReferrersSection, {
      apolloProvider: createMockApollo(
        [[getManifestReferrersQuery, handler]],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: { organizationGid: ORGANIZATION_GID },
      propsData: {
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
        ...props,
      },
      mocks: { $route: route, $router: { push } },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTable = () => wrapper.findComponent(ReferrersTable);
  const findPager = () => wrapper.findComponent(GlKeysetPagination);

  const pageTo = async (query) => {
    route.query = query;
    await waitForPromises();
  };

  afterEach(() => {
    handler = null;
  });

  describe('the read', () => {
    it('asks for the referrers of this manifest, under this repository and image', async () => {
      createComponent();
      await waitForPromises();

      expect(handler).toHaveBeenCalledTimes(1);
      expect(handler).toHaveBeenCalledWith({ ...IDENTITY_VARIABLES, first: 20 });
    });

    it('issues the read on mount, which is what the lazy tab panel defers', () => {
      createComponent();

      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  describe('while the first read is in flight', () => {
    beforeEach(() => createComponent());

    it('stands a skeleton in for the table', () => {
      expect(findSkeleton().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });

    it('renders no alert, since nothing has failed', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the read resolves', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the table over the referrers it read', () => {
      expect(findTable().props('referrers')).toEqual([mockManifestReferrer()]);
    });

    it("hands the table what it needs to address each row's own page", () => {
      expect(findTable().props()).toMatchObject({
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        subjectDigest: MANIFEST_DIGEST,
        isLoading: false,
      });
    });

    it('replaces the skeleton', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('when the manifest has no referrers', () => {
    beforeEach(async () => {
      createComponent({
        requestHandler: successHandler(
          mockManifestReferrersRepository({ referrers: mockManifestReferrers([]) }),
        ),
      });
      await waitForPromises();
    });

    it('renders the table with no rows rather than an alert', () => {
      expect(findTable().props('referrers')).toEqual([]);
      expect(findAlert().exists()).toBe(false);
    });

    it('does not stand the skeleton in, since the read has settled', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('when the read fails', () => {
    beforeEach(async () => {
      createComponent({ requestHandler: jest.fn().mockRejectedValue(new Error('Unavailable')) });
      await waitForPromises();
    });

    it('replaces the table with an alert', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findAlert().props()).toMatchObject({ variant: 'danger', dismissible: false });
      expect(findTable().exists()).toBe(false);
    });

    it('renders no skeleton once the failure has settled', () => {
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('when the digest changes after a read with rows', () => {
    let resolveReRead;

    beforeEach(async () => {
      createComponent({
        requestHandler: jest
          .fn()
          .mockResolvedValueOnce(mockRepositoryResponse(mockManifestReferrersRepository()))
          .mockReturnValueOnce(
            new Promise((resolve) => {
              resolveReRead = resolve;
            }),
          ),
      });
      await waitForPromises();
      await wrapper.setProps({ digest: MANIFEST_PARENT_DIGEST });
    });

    it('keeps the busy table over the outgoing rows rather than the skeleton', () => {
      expect(findSkeleton().exists()).toBe(false);
      expect(findTable().props()).toMatchObject({
        isLoading: true,
        referrers: [mockManifestReferrer()],
      });
    });

    it('renders the new rows once the re-read resolves', async () => {
      resolveReRead(
        mockRepositoryResponse(
          mockManifestReferrersRepository({
            manifest: {
              __typename: 'ArtifactRegistryManifestDetails',
              id: 'other-id',
              referrers: mockManifestReferrers([mockManifestReferrer({ marker: 'b' })]),
            },
          }),
        ),
      );
      await waitForPromises();

      expect(handler).toHaveBeenCalledTimes(2);
      expect(findTable().props()).toMatchObject({
        isLoading: false,
        referrers: [mockManifestReferrer({ marker: 'b' })],
        subjectDigest: MANIFEST_PARENT_DIGEST,
      });
    });
  });

  describe('when a failed read is followed by a re-read that succeeds', () => {
    beforeEach(async () => {
      createComponent({
        requestHandler: jest
          .fn()
          .mockRejectedValueOnce(new Error('Unavailable'))
          .mockResolvedValueOnce(mockRepositoryResponse(mockManifestReferrersRepository())),
      });
      await waitForPromises();
      await wrapper.setProps({ digest: MANIFEST_PARENT_DIGEST });
      await waitForPromises();
    });

    it('drops the alert and renders the table', () => {
      expect(findAlert().exists()).toBe(false);
      expect(findTable().props('referrers')).toEqual([mockManifestReferrer()]);
    });
  });

  // A manifest that stopped resolving is a failure, not a manifest nothing attests to, and the
  // two must not present alike.
  describe.each`
    case                | repository
    ${'the repository'} | ${null}
    ${'the manifest'}   | ${mockManifestReferrersRepository({ manifest: null })}
    ${'the connection'} | ${mockManifestReferrersRepository({ referrers: null })}
  `('when $case does not resolve', ({ repository }) => {
    beforeEach(async () => {
      createComponent({ requestHandler: successHandler(repository) });
      await waitForPromises();
    });

    it('renders the alert rather than an empty table', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('the status it reports upward, which drives the page live region', () => {
    const emittedStatuses = () => wrapper.emitted('status-changed').map(([status]) => status);

    it('reports the read as it lands, so the page can announce each page', async () => {
      createComponent();

      expect(emittedStatuses()).toEqual([{ isLoading: true, hasError: false, count: 0 }]);

      await waitForPromises();

      expect(emittedStatuses()).toEqual([
        { isLoading: true, hasError: false, count: 0 },
        { isLoading: false, hasError: false, count: 1 },
      ]);
    });

    it('reports a failure rather than an empty list', async () => {
      createComponent({ requestHandler: jest.fn().mockRejectedValue(new Error('Unavailable')) });
      await waitForPromises();

      expect(emittedStatuses().at(-1)).toEqual({ isLoading: false, hasError: true, count: 0 });
    });

    it('reports an empty list as empty rather than as a failure', async () => {
      createComponent({
        requestHandler: successHandler(
          mockManifestReferrersRepository({ referrers: mockManifestReferrers([]) }),
        ),
      });
      await waitForPromises();

      expect(emittedStatuses().at(-1)).toEqual({ isLoading: false, hasError: false, count: 0 });
    });
  });

  describe('paging', () => {
    const referrersPage = (pageInfo) =>
      mockManifestReferrersRepository({ referrers: mockManifestReferrers(undefined, pageInfo) });

    it('carries the forward cursor from the route beside the page size', async () => {
      createComponent({ query: { after: FIRST_PAGE_END_CURSOR } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        ...IDENTITY_VARIABLES,
        first: 20,
        after: FIRST_PAGE_END_CURSOR,
      });
    });

    it('asks backward with last rather than first, which the page params replace', async () => {
      createComponent({ query: { before: SECOND_PAGE_START_CURSOR } });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        ...IDENTITY_VARIABLES,
        first: undefined,
        last: 20,
        before: SECOND_PAGE_START_CURSOR,
        after: undefined,
      });
    });

    it('hands the pager the page the read reported', async () => {
      createComponent({
        requestHandler: successHandler(
          referrersPage({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
        ),
      });
      await waitForPromises();

      expect(findPager().props()).toMatchObject({
        hasNextPage: true,
        endCursor: FIRST_PAGE_END_CURSOR,
      });
    });

    it('pages forward through the route, dropping the cursor it came in on', async () => {
      createComponent({ query: { tab: 'referrers', before: SECOND_PAGE_START_CURSOR } });
      await waitForPromises();

      findPager().vm.$emit('next', FIRST_PAGE_END_CURSOR);

      expect(push).toHaveBeenCalledWith({
        path: REFERRERS_PATH,
        query: { tab: 'referrers', after: FIRST_PAGE_END_CURSOR },
      });
    });

    it('pages backward through the route', async () => {
      createComponent({ query: { after: FIRST_PAGE_END_CURSOR } });
      await waitForPromises();

      findPager().vm.$emit('prev', SECOND_PAGE_START_CURSOR);

      expect(push).toHaveBeenCalledWith({
        path: REFERRERS_PATH,
        query: { before: SECOND_PAGE_START_CURSOR },
      });
    });

    it('disables the pager while a page is in flight, then hands it back', async () => {
      createComponent();

      expect(findPager().props('disabled')).toBe(true);

      await waitForPromises();

      expect(findPager().props('disabled')).toBe(false);
    });

    it('re-reads a page it has already held, rather than serving it from the cache', async () => {
      createComponent();
      await waitForPromises();

      await pageTo({ after: FIRST_PAGE_END_CURSOR });
      await pageTo({});

      expect(handler).toHaveBeenCalledTimes(3);
    });

    it('blanks the pager when a page already on screen fails to move', async () => {
      createComponent({
        requestHandler: jest.fn((variables) =>
          variables.after
            ? Promise.reject(new Error('Bad Request'))
            : Promise.resolve(
                mockRepositoryResponse(
                  referrersPage({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
                ),
              ),
        ),
      });
      await waitForPromises();

      expect(findPager().props('hasNextPage')).toBe(true);

      await pageTo({ after: FIRST_PAGE_END_CURSOR });

      expect(findAlert().exists()).toBe(true);
      expect(findPager().props()).toMatchObject({ hasNextPage: false, hasPreviousPage: false });
    });

    it('hands the pager no page when the first read fails', async () => {
      createComponent({
        requestHandler: jest.fn((variables) =>
          variables.after
            ? Promise.reject(new Error('Bad Request'))
            : Promise.resolve(
                mockRepositoryResponse(
                  referrersPage({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
                ),
              ),
        ),
        query: { after: FIRST_PAGE_END_CURSOR },
      });
      await waitForPromises();

      expect(findAlert().exists()).toBe(true);
      expect(findPager().props()).toMatchObject({ hasNextPage: false, hasPreviousPage: false });
    });
  });
});
