import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import { typePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import clearRepositoryCacheMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/clear_repository_cache.mutation.graphql';
import dissociateUpstreamRepositoryMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/dissociate_upstream_repository.mutation.graphql';
import UpstreamRepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repository_actions.vue';
import {
  mockClearRepositoryCacheResponse,
  mockDeniedRepositoryPermissions,
  mockDissociateUpstreamRepositoryResponse,
  mockRepositoryPermissions,
  mockUpstreamSummary,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('ArtifactRegistryUpstreamRepositoryActions', () => {
  let wrapper;
  let mockApollo;
  let cache;
  let clearHandler;
  let dissociateHandler;

  const mockToast = { show: jest.fn() };

  const remoteUpstream = mockUpstreamSummary({ name: 'maven-central-proxy', kind: 'REMOTE' });
  const hostedUpstream = mockUpstreamSummary({ name: 'payments-releases', kind: 'HOSTED' });

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);
  const findItemTexts = () => findItems().wrappers.map((item) => item.props('item').text);
  const findEditItem = () => wrapper.findComponentByTestId('edit-upstream-repository');
  const findClearCacheItem = () => wrapper.findComponentByTestId('clear-upstream-cache');
  const findRemoveItem = () => wrapper.findComponentByTestId('remove-upstream-repository');

  const createComponent = ({
    upstreamRepository = remoteUpstream,
    repositoryPermissions = mockRepositoryPermissions(),
  } = {}) => {
    clearHandler = jest.fn().mockResolvedValue(mockClearRepositoryCacheResponse());
    dissociateHandler = jest.fn().mockResolvedValue(mockDissociateUpstreamRepositoryResponse());

    mockApollo = createMockApollo(
      [
        [clearRepositoryCacheMutation, clearHandler],
        [dissociateUpstreamRepositoryMutation, dissociateHandler],
      ],
      {},
      {
        typePolicies: { ...globalTypePolicies, ...typePolicies },
      },
    );
    cache = mockApollo.clients.defaultClient.cache;

    wrapper = shallowMountExtended(UpstreamRepositoryActions, {
      apolloProvider: mockApollo,
      propsData: {
        upstreamRepository,
        associationId: 'a1000000-0000-4000-8000-000000000001',
        repository: {
          name: 'maven-virtual',
          format: 'MAVEN',
        },
        permissions: repositoryPermissions,
      },
      mocks: { $toast: mockToast },
    });
  };

  const clearCache = async () => {
    findClearCacheItem().props('item').action();
    await waitForPromises();
  };

  const detailKey = (name) =>
    cache.identify({ __typename: 'ArtifactRegistryRepositoryDetails', name });

  const cachedDetails = (name) => cache.extract()[detailKey(name)];

  // Referenced from ROOT_QUERY, as a real read leaves them: an unreachable entry would be swept
  // by the helper's own `cache.gc()` and the eviction would look broader than it is.
  const seedDetailEntries = (...names) => {
    cache.restore({
      ROOT_QUERY: {
        __typename: 'Query',
        ...Object.fromEntries(names.map((name) => [name, { __ref: detailKey(name) }])),
      },
      ...Object.fromEntries(
        names.map((name) => [
          detailKey(name),
          { __typename: 'ArtifactRegistryRepositoryDetails', name },
        ]),
      ),
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('names the upstream in the toggle, which renders as an icon alone', () => {
    expect(findDropdown().props('toggleText')).toBe('More actions for maven-central-proxy');
  });

  it('renders the toggle as an icon-only tertiary button', () => {
    expect(findDropdown().props()).toMatchObject({
      icon: 'ellipsis_v',
      textSrOnly: true,
      category: 'tertiary',
      noCaret: true,
      placement: 'bottom-end',
    });
  });

  describe('the Edit repository item', () => {
    it('routes to the edit form for the upstream, addressed by its name', () => {
      expect(findEditItem().props('item').to).toEqual({
        name: 'repository_edit',
        params: { id: 'maven-central-proxy' },
      });
    });
  });

  describe('on a remote-source row', () => {
    it('adds Clear cache before Edit repository, and ends with Remove repository', () => {
      expect(findItemTexts()).toEqual(['Clear cache', 'Edit repository', 'Remove repository']);
    });
  });

  describe('on a hosted-source row', () => {
    beforeEach(() => {
      createComponent({ upstreamRepository: hostedUpstream });
    });

    it('carries Edit repository and ends with Remove repository', () => {
      expect(findItemTexts()).toEqual(['Edit repository', 'Remove repository']);
      expect(findClearCacheItem().exists()).toBe(false);
    });
  });

  describe('permission gating', () => {
    describe.each`
      description                                                         | upstreamPermissions                    | repositoryPermissions                                 | items
      ${'the upstream denies updateRepository'}                           | ${{ updateRepository: false }}         | ${{}}                                                 | ${['Clear cache', 'Remove repository']}
      ${'the upstream denies deleteArtifact'}                             | ${{ deleteArtifact: false }}           | ${{}}                                                 | ${['Edit repository', 'Remove repository']}
      ${'the page repository denies deleteRepositoryUpstream'}            | ${{}}                                  | ${{ deleteRepositoryUpstream: false }}                | ${['Clear cache', 'Edit repository']}
      ${'the page repository denies updateRepository and deleteArtifact'} | ${{}}                                  | ${{ updateRepository: false, deleteArtifact: false }} | ${['Clear cache', 'Edit repository', 'Remove repository']}
      ${'the upstream denies deleteRepositoryUpstream only'}              | ${{ deleteRepositoryUpstream: false }} | ${{}}                                                 | ${['Clear cache', 'Edit repository', 'Remove repository']}
    `('when $description', ({ upstreamPermissions, repositoryPermissions, items }) => {
      beforeEach(() => {
        createComponent({
          upstreamRepository: mockUpstreamSummary({
            name: 'maven-central-proxy',
            kind: 'REMOTE',
            userPermissions: mockRepositoryPermissions(upstreamPermissions),
          }),
          repositoryPermissions: mockRepositoryPermissions(repositoryPermissions),
        });
      });

      it('renders only the allowed items', () => {
        expect(findItemTexts()).toEqual(items);
      });
    });

    describe('when every item is denied', () => {
      beforeEach(() => {
        createComponent({
          upstreamRepository: mockUpstreamSummary({
            name: 'maven-central-proxy',
            kind: 'REMOTE',
            userPermissions: mockDeniedRepositoryPermissions(),
          }),
          repositoryPermissions: mockDeniedRepositoryPermissions(),
        });
      });

      it('renders no toggle', () => {
        expect(findDropdown().exists()).toBe(false);
      });
    });

    describe('when a hosted row allows Clear cache alone', () => {
      beforeEach(() => {
        createComponent({
          upstreamRepository: mockUpstreamSummary({
            name: 'payments-releases',
            kind: 'HOSTED',
            userPermissions: mockDeniedRepositoryPermissions({ deleteArtifact: true }),
          }),
          repositoryPermissions: mockDeniedRepositoryPermissions(),
        });
      });

      it('renders no toggle', () => {
        expect(findDropdown().exists()).toBe(false);
      });
    });

    describe('when neither verdict block arrived', () => {
      beforeEach(() => {
        createComponent({
          upstreamRepository: mockUpstreamSummary({
            name: 'maven-central-proxy',
            kind: 'REMOTE',
            userPermissions: null,
          }),
          repositoryPermissions: null,
        });
      });

      it('renders no toggle', () => {
        expect(findDropdown().exists()).toBe(false);
      });
    });
  });

  describe('clearing the cache', () => {
    describe('when the mutation resolves', () => {
      beforeEach(async () => {
        await clearCache();
      });

      it('issues the mutation once, addressing the upstream by name', () => {
        expect(clearHandler).toHaveBeenCalledTimes(1);
        expect(clearHandler).toHaveBeenCalledWith({ input: { name: 'maven-central-proxy' } });
      });

      it('reports acceptance through the toast, naming the upstream and no count', () => {
        expect(mockToast.show).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledWith(
          'Cache clear successfully scheduled for maven-central-proxy.',
        );
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('the cached details of the repositories on the page', () => {
      beforeEach(async () => {
        seedDetailEntries('maven-central-proxy', 'platform-snapshots');
        await clearCache();
      });

      it('drops the entry of the upstream that was cleared', () => {
        expect(cachedDetails('maven-central-proxy')).toBeUndefined();
      });

      it('leaves the other upstreams, which the clear does not touch', () => {
        expect(cachedDetails('platform-snapshots')).toBeDefined();
      });
    });

    describe('while a clear is in flight', () => {
      beforeEach(async () => {
        findClearCacheItem().props('item').action();
        await nextTick();
      });

      it('marks the toggle busy', () => {
        expect(findDropdown().props('loading')).toBe(true);
      });

      it('ignores a second attempt, so one clear cannot be issued twice', async () => {
        await clearCache();

        expect(clearHandler).toHaveBeenCalledTimes(1);
        expect(mockToast.show).toHaveBeenCalledTimes(1);
      });

      it('ignores a remove attempt', async () => {
        findRemoveItem().props('item').action();
        await waitForPromises();

        expect(dissociateHandler).not.toHaveBeenCalled();
      });
    });

    it('frees the toggle once the clear is accepted', async () => {
      await clearCache();

      expect(findDropdown().props('loading')).toBe(false);
    });

    describe('when the payload carries errors', () => {
      beforeEach(async () => {
        clearHandler.mockResolvedValue(
          mockClearRepositoryCacheResponse({ errors: ['Repository not found.'] }),
        );
        await clearCache();
      });

      it('surfaces the error and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Repository not found.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('frees the toggle, so the clear can be retried', () => {
        expect(findDropdown().props('loading')).toBe(false);
      });
    });

    describe('when the mutation fails outright', () => {
      beforeEach(async () => {
        clearHandler.mockRejectedValue(new Error('Artifact Registry is down'));
        await clearCache();
      });

      it('reports the failure as an alert and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('frees the toggle, so the clear can be retried', () => {
        expect(findDropdown().props('loading')).toBe(false);
      });
    });
  });

  describe('removing the upstream', () => {
    const remove = async () => {
      findRemoveItem().props('item').action();
      await waitForPromises();
    };

    const cachedUpstreams = (name) => cachedDetails(name)?.upstreamRepositories;

    const seedUpstreamLists = (...names) => {
      cache.restore({
        ROOT_QUERY: {
          __typename: 'Query',
          ...Object.fromEntries(names.map((name) => [name, { __ref: detailKey(name) }])),
        },
        ...Object.fromEntries(
          names.map((name) => [
            detailKey(name),
            { __typename: 'ArtifactRegistryRepositoryDetails', name, upstreamRepositories: [] },
          ]),
        ),
      });
    };

    it('renders the item as a danger action', () => {
      expect(findRemoveItem().props('item')).toMatchObject({
        text: 'Remove repository',
        variant: 'danger',
      });
    });

    it('names the upstream in the accessible name of the item', () => {
      expect(findRemoveItem().props('item').extraAttrs).toEqual({
        'aria-label': 'Remove repository maven-central-proxy',
      });
    });

    describe.each([
      ['remote-source', remoteUpstream, 'maven-central-proxy'],
      ['hosted-source', hostedUpstream, 'payments-releases'],
    ])('on a %s row', (_, upstreamRepository, upstreamName) => {
      beforeEach(async () => {
        createComponent({ upstreamRepository });
        seedUpstreamLists('maven-virtual', 'npm-virtual');
        await remove();
      });

      it('issues one dissociate for the page repository and the row association', () => {
        expect(dissociateHandler).toHaveBeenCalledTimes(1);
        expect(dissociateHandler).toHaveBeenCalledWith({
          input: {
            name: 'maven-virtual',
            format: 'MAVEN',
            associationId: 'a1000000-0000-4000-8000-000000000001',
          },
        });
      });

      it('toasts, naming the upstream it removed', () => {
        expect(mockToast.show).toHaveBeenCalledWith(
          `${upstreamName} removed from this virtual repository.`,
        );
      });

      it('evicts the upstream list of the page repository alone', () => {
        expect(cachedDetails('maven-virtual')).toBeDefined();
        expect(cachedUpstreams('maven-virtual')).toBeUndefined();
        expect(cachedUpstreams('npm-virtual')).toEqual([]);
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('while a removal is in flight', () => {
      beforeEach(async () => {
        findRemoveItem().props('item').action();
        await nextTick();
      });

      it('marks the toggle busy', () => {
        expect(findDropdown().props('loading')).toBe(true);
      });

      it('ignores a second attempt', async () => {
        await remove();

        expect(dissociateHandler).toHaveBeenCalledTimes(1);
      });

      it('ignores a clear cache attempt', async () => {
        await clearCache();

        expect(clearHandler).not.toHaveBeenCalled();
      });
    });

    describe('when Artifact Registry refuses the removal', () => {
      beforeEach(async () => {
        seedUpstreamLists('maven-virtual');
        dissociateHandler.mockResolvedValue(
          mockDissociateUpstreamRepositoryResponse({ errors: ['Repository is not virtual.'] }),
        );
        await remove();
      });

      it('renders the refusal in an alert and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Repository is not virtual.' });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('leaves the cached upstream list unchanged', () => {
        expect(cachedUpstreams('maven-virtual')).toEqual([]);
      });

      it('frees the toggle', () => {
        expect(findDropdown().props('loading')).toBe(false);
      });
    });

    describe('when the mutation fails outright', () => {
      beforeEach(async () => {
        dissociateHandler.mockRejectedValue(new Error('Artifact Registry is down'));
        await remove();
      });

      it('reports the failure as an alert and shows no toast', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });
  });
});
