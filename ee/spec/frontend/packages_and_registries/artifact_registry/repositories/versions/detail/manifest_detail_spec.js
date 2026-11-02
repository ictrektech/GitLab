import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { RouterLinkStub } from '@vue/test-utils';
import {
  GlAlert,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlSkeletonLoader,
  GlTab,
  GlTabs,
} from '@gitlab/ui';
import { createAlert } from '~/alert';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import waitForPromises from 'helpers/wait_for_promises';
import { observable, resetObservable } from '~/lib/utils/observable';
import BaseLayout from '~/vue_shared/components/base_layout.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import TagBadges from 'ee/packages_and_registries/artifact_registry/repositories/components/tag_badges.vue';
import ManifestDetail from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_detail.vue';
import ManifestOverview from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_overview.vue';
import ManifestSidebar from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_sidebar.vue';
import ReferrersSection from 'ee/packages_and_registries/artifact_registry/repositories/versions/detail/referrers_section.vue';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getManifestQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest.query.graphql';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import getRepositoryPermissionsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_permissions.query.graphql';
import {
  ARTIFACT_ID_FOR,
  CLIENT_BASE_URL,
  MANIFEST_DIGEST,
  MOCK_IMAGE_MEDIA_TYPE,
  MOCK_INDEX_MEDIA_TYPE,
  ORGANIZATION_GID,
  SLUG,
  mockDeleteManifestResponse,
  mockDeniedRepositoryPermissions,
  mockManifestDetails,
  mockManifestReferrersRepository,
  mockManifestRepository,
  mockRepository,
  mockRepositoryPermissions,
  mockRepositoryResponse,
} from '../../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const MANIFEST_PATH = `/${mockRepository.name}/${ARTIFACT_ID}/manifests/${MANIFEST_DIGEST}`;

const OTHER_DIGEST = `sha256:${'f0e1d2c3'.repeat(8)}`;

const ROUTE_STATE_KEY = 'artifact_registry_manifest_detail_spec_route';

const successHandler = (repository = mockManifestRepository()) =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(repository));

const failingHandler = () => jest.fn().mockRejectedValue(new Error('Unavailable'));

const referrersHandler = () =>
  jest.fn().mockResolvedValue(mockRepositoryResponse(mockManifestReferrersRepository()));

const permissionsResponse = (userPermissions) => {
  const { __typename, id, name } = mockManifestRepository();

  return mockRepositoryResponse({ __typename, id, name, userPermissions });
};

const permissionsHandler = (userPermissions = mockRepositoryPermissions()) =>
  jest.fn().mockResolvedValue(permissionsResponse(userPermissions));

describe('ArtifactRegistryManifestDetail', () => {
  let wrapper;
  let mockApollo;

  const updateArtifactName = jest.fn();
  const updateManifestName = jest.fn();

  const push = jest.fn();
  const mockToast = { show: jest.fn() };

  let referrersRequest;

  let route;

  const createComponent = ({
    handler = successHandler(),
    deleteHandler = jest.fn().mockResolvedValue(mockDeleteManifestResponse()),
    permissions = permissionsHandler(),
    digest = MANIFEST_DIGEST,
    query = {},
    mountFn = shallowMountExtended,
    apolloProvider,
  } = {}) => {
    referrersRequest = referrersHandler();
    resetObservable(ROUTE_STATE_KEY);
    route = observable(ROUTE_STATE_KEY, {
      path: MANIFEST_PATH,
      params: { id: mockRepository.name, artifactId: ARTIFACT_ID, digest },
      query,
    });

    mockApollo =
      apolloProvider ??
      createMockApollo(
        [
          [getManifestQuery, handler],
          [getManifestReferrersQuery, referrersRequest],
          [getRepositoryPermissionsQuery, permissions],
          [deleteManifestMutation, deleteHandler],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      );

    wrapper = mountFn(ManifestDetail, {
      apolloProvider: mockApollo,
      provide: {
        breadCrumbState: { updateArtifactName, updateManifestName },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      mocks: { $route: route, $router: { push }, $toast: mockToast },
      stubs: { BaseLayout, DetailLayout, PageHeading, RouterLink: RouterLinkStub },
    });
  };

  const findSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findLogo = () => wrapper.findComponent(FormatLogo);
  const findAnnouncement = () => wrapper.findByTestId('manifest-announcement');
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findDigest = () => wrapper.findByTestId('manifest-digest');
  const findKind = () => wrapper.findByTestId('manifest-kind');
  const findMediaType = () => wrapper.findByTestId('manifest-media-type');
  const findArtifactType = () => wrapper.findByTestId('manifest-artifact-type');
  const findSubjectDigest = () => wrapper.findByTestId('manifest-subject-digest');
  const findFullDigest = () => wrapper.findByTestId('manifest-full-digest');
  const findCopyButton = () => wrapper.findComponent(ClipboardButton);
  const findFormatName = () => wrapper.findByTestId('manifest-format-name');
  const findImageName = () => wrapper.findByTestId('image-name');
  const findSidebar = () => wrapper.findComponent(ManifestSidebar);
  const findOverview = () => wrapper.findComponent(ManifestOverview);
  const findReferrersSection = () => wrapper.findComponent(ReferrersSection);
  const findTabs = () => wrapper.findComponent(GlTabs);
  const findAllTabs = () => wrapper.findAllComponents(GlTab);
  const findTabTitles = () => findAllTabs().wrappers.map((tab) => tab.attributes('title'));
  const findCountBadge = () => wrapper.findByTestId('tab-counter-badge');
  const findCountSrText = () => findCountBadge().element.nextElementSibling;
  const findTabTexts = () => wrapper.findAllByRole('tab').wrappers.map((tab) => tab.text());

  describe('the read this page is about', () => {
    it('asks for the manifest the route names, within the image the route names', async () => {
      const handler = successHandler();

      createComponent({ handler });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
      });
    });
  });

  describe('while the read is in flight', () => {
    it('renders a skeleton rather than an empty page', () => {
      createComponent();

      expect(findSkeleton().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findDigest().exists()).toBe(false);
    });

    it('announces that the page is loading', () => {
      createComponent();

      expect(findAnnouncement().text()).toBe('Loading manifest details.');
    });
  });

  describe('when the registry cannot be reached', () => {
    it('renders the service-unavailable alert', async () => {
      createComponent({ handler: failingHandler() });
      await waitForPromises();

      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
      expect(findHeading().exists()).toBe(false);
    });

    it('leaves no header or actions standing over the alert when a refetch fails', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValueOnce(mockRepositoryResponse(mockManifestRepository()))
          .mockRejectedValue(new Error('Unavailable')),
      });
      await waitForPromises();

      wrapper.vm.$apollo.queries.repository.refetch().catch(() => {});
      await waitForPromises();

      expect(findAlert().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(wrapper.findComponent(GlDisclosureDropdown).exists()).toBe(false);
    });

    it('leaves the live region silent, because the alert announces itself', async () => {
      createComponent({ handler: failingHandler() });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('');
    });
  });

  describe('when the digest names no manifest of this image', () => {
    it.each`
      case                   | repository
      ${'a null manifest'}   | ${mockManifestRepository({ manifest: null })}
      ${'a null repository'} | ${null}
    `('renders the not-found view for $case', async ({ repository }) => {
      createComponent({ handler: successHandler(repository) });
      await waitForPromises();

      expect(findNotFound().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findDigest().exists()).toBe(false);
    });

    it('announces the not-found state', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ manifest: null })) });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('Page not found');
    });
  });

  describe('the header', () => {
    it('names the manifest by its short digest, not the whole one', async () => {
      createComponent();
      await waitForPromises();

      expect(findDigest().text()).toBe('a1b2c3d4a1b2');
    });

    it.each`
      format      | label
      ${'DOCKER'} | ${'Docker'}
      ${'OCI'}    | ${'OCI'}
    `(
      'renders the $format logo beside it, named for a reader who cannot see it',
      async ({ format, label }) => {
        createComponent({ handler: successHandler(mockManifestRepository({ format })) });
        await waitForPromises();

        expect(findLogo().props('format')).toBe(format);
        expect(findFormatName().text()).toBe(label);
      },
    );

    it('renders the kind as a badge beside the heading rather than inside it', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findKind().classes()).toContain('gl-badge');
      expect(findHeading().element.contains(findKind().element)).toBe(false);
    });

    it('names the media type, which is what tells one manifest kind from another', async () => {
      createComponent();
      await waitForPromises();

      expect(findMediaType().text()).toBe(`Media type: ${MOCK_INDEX_MEDIA_TYPE}`);
    });

    it('renders the whole digest, which the short one cannot be expanded back into', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Index digest: ${MANIFEST_DIGEST}`);
    });

    it('offers the whole digest to the clipboard, not the shortened one', async () => {
      createComponent();
      await waitForPromises();

      expect(findCopyButton().props('text')).toBe(MANIFEST_DIGEST);
    });

    it('names what the copy button copies', async () => {
      createComponent();
      await waitForPromises();

      expect(findCopyButton().props('title')).toBe('Copy digest');
    });

    it('names the image the manifest belongs to, not only in the trail', async () => {
      createComponent();
      await waitForPromises();

      expect(findImageName().text()).toBe('payment-service');
    });

    it('renders no image line when the image did not resolve', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(findImageName().exists()).toBe(false);
    });

    it('renders the populated state alone, with no state left over beside it', async () => {
      createComponent();
      await waitForPromises();

      expect(findSkeleton().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
    });
  });

  describe('a referrer manifest, which the list reaches this page from', () => {
    const referrer = (overrides = {}) =>
      successHandler(
        mockManifestRepository({
          manifest: mockManifestDetails({
            mediaType: MOCK_IMAGE_MEDIA_TYPE,
            subjectDigest: `sha256:${'b2c3d4e5'.repeat(8)}`,
            artifactType: 'application/vnd.dev.cosign.artifact.sig.v1+json',
            ...overrides,
          }),
        }),
      );

    it('calls a cosign signature a signature, the same name the manifests list gives it', async () => {
      createComponent({ handler: referrer() });
      await waitForPromises();

      expect(findKind().text()).toBe('Signature');
    });

    it('names the raw artifact type in the description, where there is room for it', async () => {
      createComponent({ handler: referrer(), mountFn: mountExtended });
      await waitForPromises();

      expect(findArtifactType().text()).toBe(
        'Artifact type: application/vnd.dev.cosign.artifact.sig.v1+json',
      );
    });

    it('names the manifest it attests to, which is the point of a referrer', async () => {
      createComponent({ handler: referrer(), mountFn: mountExtended });
      await waitForPromises();

      expect(findSubjectDigest().text()).toBe(`Subject digest: sha256:${'b2c3d4e5'.repeat(8)}`);
    });

    it('labels the digest neutrally, because it is neither an index nor a plain image', async () => {
      createComponent({ handler: referrer() });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Manifest digest: ${MANIFEST_DIGEST}`);
    });

    it('falls back to naming it a referrer when it declares no artifact type', async () => {
      createComponent({ handler: referrer({ artifactType: null }), mountFn: mountExtended });
      await waitForPromises();

      expect(findKind().text()).toBe('Referrer');
      expect(findArtifactType().exists()).toBe(false);
    });

    it('names an unrecognised artifact type a referrer, and still prints the type', async () => {
      createComponent({
        handler: referrer({ artifactType: 'application/vnd.acme.custom+json' }),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findKind().text()).toBe('Referrer');
      expect(findArtifactType().text()).toBe('Artifact type: application/vnd.acme.custom+json');
    });
  });

  describe('what the header calls the manifest', () => {
    const withManifest = (overrides) =>
      successHandler(mockManifestRepository({ manifest: mockManifestDetails(overrides) }));

    it.each`
      childrenCount | label
      ${3}          | ${'Index · 3 platforms'}
      ${1}          | ${'Index · 1 platform'}
    `('reads an index of $childrenCount as $label', async ({ childrenCount, label }) => {
      createComponent({ handler: withManifest({ childrenCount }) });
      await waitForPromises();

      expect(findKind().text()).toBe(label);
    });

    it('reads a single-platform manifest as an image, with no platform count', async () => {
      createComponent({ handler: withManifest({ mediaType: MOCK_IMAGE_MEDIA_TYPE }) });
      await waitForPromises();

      expect(findKind().text()).toBe('Image');
    });

    it('reads an index of no platforms as an index, not as an image', async () => {
      createComponent({ handler: withManifest({ childrenCount: 0 }) });
      await waitForPromises();

      expect(findKind().text()).toBe('Index · 0 platforms');
    });

    it('labels the digest line by kind, so the two reads are distinguishable', async () => {
      createComponent({
        handler: withManifest({ mediaType: MOCK_IMAGE_MEDIA_TYPE }),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findFullDigest().text()).toBe(`Image digest: ${MANIFEST_DIGEST}`);
    });
  });

  describe('the live region', () => {
    it('announces politely and whole, and is reachable only to a screen reader', async () => {
      createComponent();
      await waitForPromises();

      expect(findAnnouncement().attributes()).toMatchObject({
        'aria-live': 'polite',
        'aria-atomic': 'true',
      });
      expect(findAnnouncement().classes()).toContain('gl-sr-only');
    });
  });

  describe('the breadcrumb trail', () => {
    it('publishes both names once, not an empty pair then the resolved one', async () => {
      createComponent();
      await waitForPromises();

      expect(updateArtifactName.mock.calls).toEqual([['payment-service']]);
      expect(updateManifestName.mock.calls).toEqual([['a1b2c3d4a1b2']]);
    });

    it('publishes nothing while the read is in flight, so a resolved name is not blanked', () => {
      createComponent();

      expect(updateArtifactName).not.toHaveBeenCalled();
      expect(updateManifestName).not.toHaveBeenCalled();
    });

    // The page is reachable from a sibling manifest now, and the component instance is reused
    // across that navigation, so a name read off the payload would lag a route change.
    it('names the manifest the route asks for, not the one still loaded', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ digest: OTHER_DIGEST }) }),
        ),
      });
      await waitForPromises();

      expect(updateManifestName.mock.calls).toEqual([['a1b2c3d4a1b2']]);
    });

    it('publishes an empty image name once the read settles without one', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(updateArtifactName).toHaveBeenCalledWith('');
      expect(updateArtifactName).not.toHaveBeenCalledWith('payment-service');
    });
  });

  describe('when the organization itself does not resolve', () => {
    it('reads it as not found rather than throwing on the way in', async () => {
      const handler = jest.fn().mockResolvedValue({ data: { organization: null } });

      createComponent({ handler });
      await waitForPromises();

      expect(findNotFound().exists()).toBe(true);
    });
  });

  describe('the tag badges', () => {
    const findTagBadges = () => wrapper.findComponent(TagBadges);

    it('hands the manifest tags to the badges in the order served', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: ['v2', 'latest'] }) }),
        ),
      });
      await waitForPromises();

      expect(findTagBadges().props('tags')).toEqual(['v2', 'latest']);
    });

    it('hands an empty list when the manifest carries a null list', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ tags: null }) }),
        ),
      });
      await waitForPromises();

      expect(findTagBadges().props('tags')).toEqual([]);
    });

    it('renders them between the digest and the kind, as the design orders them', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      const order = wrapper
        .findAll(
          '[data-testid="manifest-digest"], [data-testid="tag-badge"], [data-testid="manifest-kind"]',
        )
        .wrappers.map((node) => node.attributes('data-testid'));

      expect(order).toEqual([
        'manifest-digest',
        'tag-badge',
        'tag-badge',
        'tag-badge',
        'manifest-kind',
      ]);
    });

    it('distinguishes a tag from the kind by variant, not by position alone', async () => {
      createComponent({ mountFn: mountExtended });
      await waitForPromises();

      expect(wrapper.findByTestId('tag-badge').classes()).toContain('badge-info');
      expect(findKind().classes()).toContain('badge-neutral');
    });
  });

  describe('the sidebar', () => {
    it('hands it the repository, the manifest, and the image the route names', async () => {
      createComponent();
      await waitForPromises();

      expect(findSidebar().props()).toMatchObject({
        repository: expect.objectContaining({ name: mockRepository.name }),
        manifest: expect.objectContaining({ digest: MANIFEST_DIGEST }),
        artifactId: ARTIFACT_ID,
      });
    });

    it.each([
      ['the read is in flight', () => jest.fn().mockReturnValue(new Promise(() => {}))],
      ['the registry cannot be reached', () => jest.fn().mockRejectedValue(new Error('nope'))],
      [
        'the digest names no manifest',
        () => successHandler(mockManifestRepository({ manifest: null })),
      ],
    ])('renders no sidebar when %s', async (_, handler) => {
      createComponent({ handler: handler() });
      await waitForPromises();

      expect(findSidebar().exists()).toBe(false);
    });
  });

  describe('the result announcement', () => {
    it('names the tab, the manifest and the image it belongs to', async () => {
      createComponent();
      await waitForPromises();

      expect(findAnnouncement().text()).toBe(
        'Overview tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });

    it('names the manifest alone when the image did not resolve', async () => {
      createComponent({ handler: successHandler(mockManifestRepository({ image: null })) });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe('Overview tab for manifest a1b2c3d4a1b2.');
    });

    it('names the tab the query asks for, so a switch is announced', async () => {
      createComponent({ query: { tab: 'referrers' } });
      await waitForPromises();

      expect(findAnnouncement().text()).toBe(
        'Referrers tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });
  });

  describe('the referrers tab announcement', () => {
    const emitStatus = async (status) => {
      findReferrersSection().vm.$emit('status-changed', status);
      await nextTick();
    };

    beforeEach(async () => {
      createComponent({ query: { tab: 'referrers' } });
      await waitForPromises();
    });

    it('announces the read while a page is in flight, so paging is not silent', async () => {
      await emitStatus({ isLoading: true, hasError: false, count: 0 });

      expect(findAnnouncement().text()).toBe('Loading referrers.');
    });

    it('announces an empty list rather than the tab it sits on', async () => {
      await emitStatus({ isLoading: false, hasError: false, count: 0 });

      expect(findAnnouncement().text()).toBe('Nothing refers to this manifest.');
    });

    it('leaves the live region to the alert when the read failed', async () => {
      await emitStatus({ isLoading: false, hasError: true, count: 0 });

      expect(findAnnouncement().text()).toBe('');
    });

    it('names the tab once rows are on screen, which is what re-announces a new page', async () => {
      await emitStatus({ isLoading: false, hasError: false, count: 20 });

      expect(findAnnouncement().text()).toBe(
        'Referrers tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });

    it('stops speaking for the section once the reader leaves the tab', async () => {
      await emitStatus({ isLoading: false, hasError: false, count: 0 });

      route.query = { tab: 'overview' };
      await nextTick();

      expect(findAnnouncement().text()).toBe(
        'Overview tab for manifest a1b2c3d4a1b2 of payment-service.',
      );
    });
  });

  describe('the tabs', () => {
    it('renders Overview and Referrers only', async () => {
      createComponent();
      await waitForPromises();

      expect(findTabTitles()).toEqual(['Overview', 'Referrers']);
    });

    it('renders no tabs while the read is still in flight', async () => {
      createComponent({ handler: jest.fn(() => new Promise(() => {})) });
      await waitForPromises();

      expect(findTabs().exists()).toBe(false);
    });

    it.each([
      ['the registry cannot be reached', () => failingHandler()],
      [
        'the digest names no manifest',
        () => successHandler(mockManifestRepository({ manifest: null })),
      ],
    ])('renders no tabs when %s', async (_, handler) => {
      createComponent({ handler: handler() });
      await waitForPromises();

      expect(findTabs().exists()).toBe(false);
    });

    it('counts the referrers on the Referrers tab alone', async () => {
      createComponent();
      await waitForPromises();

      expect(findAllTabs().wrappers.map((tab) => tab.props('tabCount'))).toEqual([null, 2]);
    });
  });

  describe('the overview panel', () => {
    const mountTab = async (query = {}) => {
      createComponent({ query, mountFn: mountExtended });
      await waitForPromises();
    };

    it('mounts the overview on the Overview tab, which is the default', async () => {
      await mountTab();

      expect(findOverview().props()).toMatchObject({
        format: 'DOCKER',
        name: mockRepository.name,
        imageName: 'payment-service',
      });
      expect(findOverview().props('manifest').digest).toBe(MANIFEST_DIGEST);
    });

    it('mounts no overview while the Referrers tab is the active one', async () => {
      await mountTab({ tab: 'referrers' });

      expect(findOverview().exists()).toBe(false);
    });

    it('mounts no overview when the digest names no manifest', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ manifest: null })),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findOverview().exists()).toBe(false);
    });

    it('hands the overview an empty name when the image did not resolve', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ image: null })),
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findOverview().props('imageName')).toBe('');
    });
  });

  describe('the referrers panel', () => {
    const mountTab = async (query) => {
      createComponent({ query, mountFn: mountExtended });
      await waitForPromises();
    };

    it('mounts the referrers section when the Referrers tab is the active one', async () => {
      await mountTab({ tab: 'referrers' });

      expect(findReferrersSection().props()).toStrictEqual({
        name: mockRepository.name,
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
      });
    });

    it.each([{}, { tab: 'overview' }, { tab: 'nonsense' }])(
      'asks Artifact Registry for no referrers while the query reads %p',
      async (query) => {
        await mountTab(query);

        expect(findReferrersSection().exists()).toBe(false);
        expect(referrersRequest).not.toHaveBeenCalled();
      },
    );

    it('issues the referrers read once the Referrers tab is selected', async () => {
      await mountTab({ tab: 'referrers' });

      expect(referrersRequest).toHaveBeenCalledTimes(1);
    });

    it('hands the section the digest the read resolved, not the one in the route', async () => {
      createComponent({
        handler: successHandler(
          mockManifestRepository({ manifest: mockManifestDetails({ digest: OTHER_DIGEST }) }),
        ),
        query: { tab: 'referrers' },
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findReferrersSection().props('digest')).toBe(OTHER_DIGEST);
    });

    it('mounts no referrers section when the digest names no manifest', async () => {
      createComponent({
        handler: successHandler(mockManifestRepository({ manifest: null })),
        query: { tab: 'referrers' },
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findReferrersSection().exists()).toBe(false);
    });
  });

  describe('the referrers count as it reaches the page', () => {
    const withCount = (referrersCount) =>
      successHandler(mockManifestRepository({ manifest: mockManifestDetails({ referrersCount }) }));

    const mountWith = async (handler) => {
      createComponent({ handler, mountFn: mountExtended });
      await waitForPromises();
    };

    it('renders the count in a badge, hidden from a screen reader', async () => {
      await mountWith(successHandler());

      expect(findCountBadge().text()).toBe('2');
      expect(findCountBadge().attributes('aria-hidden')).toBe('true');
    });

    it('names the count for a screen reader instead, since the badge is hidden', async () => {
      await mountWith(successHandler());

      expect(findCountSrText().textContent).toBe('2 referrers');
    });

    it('names a single referrer in the singular', async () => {
      await mountWith(withCount(1));

      expect(findCountBadge().text()).toBe('1');
      expect(findCountSrText().textContent).toBe('1 referrer');
    });

    it('hides the Referrers tab on an exact zero', async () => {
      await mountWith(withCount(0));

      expect(findTabTexts()).toEqual(['Overview']);
      expect(findCountBadge().exists()).toBe(false);
    });

    it('lands on Overview when the query asks for the hidden Referrers tab', async () => {
      createComponent({
        handler: withCount(0),
        query: { tab: 'referrers' },
        mountFn: mountExtended,
      });
      await waitForPromises();

      expect(findTabs().props('value')).toBe(0);
      expect(findReferrersSection().exists()).toBe(false);
      expect(referrersRequest).not.toHaveBeenCalled();
    });

    it('renders no badge at all when the count did not resolve', async () => {
      await mountWith(withCount(null));

      expect(findCountBadge().exists()).toBe(false);
      expect(findTabTexts()).toEqual(['Overview', 'Referrers']);
    });
  });

  describe('which tab the query parameter selects', () => {
    it.each`
      query                   | index | outcome
      ${{}}                   | ${0}  | ${'an absent value lands on Overview'}
      ${{ tab: 'overview' }}  | ${0}  | ${'overview selects Overview'}
      ${{ tab: 'referrers' }} | ${1}  | ${'referrers selects Referrers'}
      ${{ tab: 'manifest' }}  | ${0}  | ${'an unrecognized value lands on Overview'}
      ${{ tab: '' }}          | ${0}  | ${'an empty value lands on Overview'}
    `('$outcome', async ({ query, index }) => {
      createComponent({ query });
      await waitForPromises();

      expect(findTabs().props('value')).toBe(index);
    });
  });

  describe('when a tab is selected', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('records the tab in the query rather than in component state', () => {
      findTabs().vm.$emit('input', 1);

      expect(push).toHaveBeenCalledWith({
        path: MANIFEST_PATH,
        query: { tab: 'referrers' },
      });
    });

    it('does not push when the tab is already active', () => {
      findTabs().vm.$emit('input', 0);

      expect(push).not.toHaveBeenCalled();
    });
  });

  describe('when a tab is selected with something else already in the query', () => {
    it('keeps the rest of the query, so another page-level selection survives', async () => {
      createComponent({ query: { sort: 'created_desc' } });
      await waitForPromises();

      findTabs().vm.$emit('input', 1);

      expect(push).toHaveBeenCalledWith({
        path: MANIFEST_PATH,
        query: { sort: 'created_desc', tab: 'referrers' },
      });
    });

    it('drops the referrers cursor when the reader leaves the tab', async () => {
      createComponent({ query: { tab: 'referrers', after: 'a-referrers-cursor' } });
      await waitForPromises();

      findTabs().vm.$emit('input', 0);

      expect(push).toHaveBeenCalledWith({
        path: MANIFEST_PATH,
        query: { tab: 'overview' },
      });
    });
  });

  describe('deleting the manifest', () => {
    const DIGEST = 'sha256:a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
    const IMAGE_ID = '01937b2e-0000-7000-8000-000000000001';

    const findActions = () => wrapper.findComponent(GlDisclosureDropdown);
    const findDeleteItem = () => wrapper.findComponent(GlDisclosureDropdownItem);
    const findDeleteButton = () => wrapper.findByTestId('delete-manifest');
    const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);

    const mountLoaded = async (options = {}) => {
      createComponent({ mountFn: mountExtended, ...options });
      await waitForPromises();
    };

    const openConfirmation = async () => {
      await findActions().find('button[aria-expanded]').trigger('click');
      findDeleteButton().find('button').trigger('click');
      await nextTick();
    };

    const confirmDeletion = async () => {
      findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
      await waitForPromises();
    };

    it('offers a delete action in the kebab, marked destructive', async () => {
      await mountLoaded();

      expect(findActions().props('toggleText')).toBe('More actions for a1b2c3d4a1b2');
      expect(findDeleteItem().props('item')).toMatchObject({
        text: 'Delete manifest',
        variant: 'danger',
      });
    });

    it('starts with the confirmation closed', async () => {
      await mountLoaded();

      expect(findDeleteModal().props('target')).toBeNull();
    });

    describe.each`
      outcome                           | handler
      ${'the read is still loading'}    | ${() => jest.fn().mockReturnValue(new Promise(() => {}))}
      ${'the read fails'}               | ${() => failingHandler()}
      ${'the digest names no manifest'} | ${() => successHandler(mockManifestRepository({ manifest: null }))}
    `('when $outcome', ({ handler }) => {
      it('offers no actions', async () => {
        await mountLoaded({ handler: handler() });

        expect(findActions().exists()).toBe(false);
      });
    });

    describe.each`
      outcome                                  | permissions
      ${'the verdict denies'}                  | ${() => permissionsHandler(mockDeniedRepositoryPermissions())}
      ${'the permission block is null'}        | ${() => permissionsHandler(null)}
      ${'the permission block has no verdict'} | ${() => permissionsHandler({ __typename: 'ArtifactRegistryRepositoryPermissions' })}
      ${'the repository does not resolve'}     | ${() => jest.fn().mockResolvedValue(mockRepositoryResponse(null))}
      ${'the permission read fails'}           | ${() => jest.fn().mockRejectedValue(new Error('Unavailable'))}
      ${'the permission read is in flight'}    | ${() => jest.fn().mockReturnValue(new Promise(() => {}))}
    `('when $outcome', ({ permissions }) => {
      beforeEach(async () => {
        await mountLoaded({ permissions: permissions() });
      });

      it('renders no delete item and no toggle', () => {
        expect(findDeleteItem().exists()).toBe(false);
        expect(findActions().exists()).toBe(false);
      });
    });

    describe('when the cache already holds a denying verdict', () => {
      let handler;
      let permissions;
      let answer;

      beforeEach(async () => {
        handler = successHandler();
        permissions = jest
          .fn()
          .mockResolvedValueOnce(permissionsResponse(mockDeniedRepositoryPermissions()))
          .mockReturnValueOnce(
            new Promise((resolve) => {
              answer = resolve;
            }),
          );

        await mountLoaded({ handler, permissions });
        const apolloProvider = mockApollo;
        wrapper.destroy();

        createComponent({ mountFn: mountExtended, apolloProvider });
        await nextTick();
      });

      it('renders the manifest from the cache without reading it again', () => {
        expect(handler).toHaveBeenCalledTimes(1);
        expect(findDigest().text()).toBe('a1b2c3d4a1b2');
      });

      it('re-reads the verdict from the network', () => {
        expect(permissions).toHaveBeenCalledTimes(2);
      });

      it('renders no delete item while the re-read is in flight', () => {
        expect(findDeleteItem().exists()).toBe(false);
      });

      describe('when the network answer allows', () => {
        beforeEach(async () => {
          answer(permissionsResponse(mockRepositoryPermissions()));
          await waitForPromises();
        });

        it('renders the delete item', () => {
          expect(findDeleteItem().exists()).toBe(true);
        });
      });
    });

    describe('when the cache already holds an allowing verdict', () => {
      let answer;
      let fail;

      beforeEach(async () => {
        const permissions = jest
          .fn()
          .mockResolvedValueOnce(permissionsResponse(mockRepositoryPermissions()))
          .mockReturnValueOnce(
            new Promise((resolve, reject) => {
              answer = resolve;
              fail = reject;
            }),
          );

        await mountLoaded({ permissions });
        const apolloProvider = mockApollo;
        wrapper.destroy();

        createComponent({ mountFn: mountExtended, apolloProvider });
        await waitForPromises();
      });

      it('renders no delete item while the re-read is in flight', () => {
        expect(findDeleteItem().exists()).toBe(false);
      });

      describe('when the network answer denies', () => {
        beforeEach(async () => {
          answer(permissionsResponse(mockDeniedRepositoryPermissions()));
          await waitForPromises();
        });

        it('renders no delete item', () => {
          expect(findDeleteItem().exists()).toBe(false);
        });
      });

      describe('when the network read fails', () => {
        beforeEach(async () => {
          fail(new Error('Unavailable'));
          await waitForPromises();
        });

        it('renders no delete item rather than falling back to the cached verdict', () => {
          expect(findDeleteItem().exists()).toBe(false);
        });
      });
    });

    describe('when the delete action is chosen', () => {
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockResolvedValue(mockDeleteManifestResponse());
        await mountLoaded({ deleteHandler });
        await openConfirmation();
      });

      it('opens the confirmation on this manifest and sends nothing yet', () => {
        expect(findDeleteModal().props()).toMatchObject({
          title: 'Delete manifest?',
          name: 'a1b2c3d4a1b2',
          actionText: 'Delete manifest',
          body: 'This action permanently deletes manifest %{name} and any tags pointing to it. Its child manifests are not deleted and will remain in Artifact Registry as untagged, standalone manifests. This action cannot be undone.',
        });
        expect(findDeleteModal().props('target')).toMatchObject({ digest: DIGEST });
        expect(deleteHandler).not.toHaveBeenCalled();
      });
    });

    describe.each([
      [
        'an image',
        { mediaType: MOCK_IMAGE_MEDIA_TYPE },
        'This action permanently deletes manifest %{name} and any tags pointing to it. This action cannot be undone.',
      ],
      [
        'a signature',
        {
          mediaType: MOCK_IMAGE_MEDIA_TYPE,
          subjectDigest: `sha256:${'b2c3d4e5'.repeat(8)}`,
          artifactType: 'application/vnd.dev.cosign.artifact.sig.v1+json',
        },
        'This action permanently deletes signature %{name} and any tags pointing to it. The image it signs will then verify as unsigned. This action cannot be undone.',
      ],
    ])('when the manifest is %s', (_, overrides, body) => {
      it('words the confirmation for that kind', async () => {
        await mountLoaded({
          handler: successHandler(
            mockManifestRepository({ manifest: mockManifestDetails(overrides) }),
          ),
        });
        await openConfirmation();

        expect(findDeleteModal().props('body')).toBe(body);
      });
    });

    describe.each`
      destination                                | params
      ${'another manifest'}                      | ${{ digest: OTHER_DIGEST }}
      ${'the same digest in another image'}      | ${{ artifactId: 'another-artifact-id' }}
      ${'the same digest in another repository'} | ${{ id: 'another-repository' }}
    `('when the route moves to $destination', ({ params }) => {
      beforeEach(async () => {
        await mountLoaded();
        await openConfirmation();

        route.params = { ...route.params, ...params };
        await nextTick();
      });

      it('closes the confirmation', () => {
        expect(findDeleteModal().props('target')).toBeNull();
      });
    });

    describe('when the route moves to another repository while its verdict is in flight', () => {
      beforeEach(async () => {
        const permissions = jest
          .fn()
          .mockResolvedValueOnce(permissionsResponse(mockRepositoryPermissions()))
          .mockReturnValueOnce(new Promise(() => {}));
        await mountLoaded({ permissions });

        route.params = { ...route.params, id: 'another-repository' };
        await waitForPromises();
      });

      it('renders no delete item', () => {
        expect(findDeleteItem().exists()).toBe(false);
      });
    });

    describe('when the confirmation is accepted', () => {
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockResolvedValue(mockDeleteManifestResponse());
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        await confirmDeletion();
      });

      it('addresses the manifest by digest within its image and repository', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: 'my-repository', imageId: IMAGE_ID, digest: DIGEST },
        });
      });

      it('reports the delete as scheduled rather than done', () => {
        expect(mockToast.show).toHaveBeenCalledWith(
          'Manifest successfully scheduled for deletion.',
        );
      });

      it('navigates to the version list', () => {
        expect(push).toHaveBeenCalledWith({
          name: 'artifact_versions',
          params: { id: 'my-repository', artifactId: IMAGE_ID },
        });
      });

      it('raises no alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the delete is refused because other manifests index it', () => {
      const conflict = `Manifest ${DIGEST} was not deleted because it is indexed by other manifests: sha256:${'c3d4e5f6'.repeat(8)}.`;

      beforeEach(async () => {
        const deleteHandler = jest
          .fn()
          .mockResolvedValue(mockDeleteManifestResponse({ errors: [conflict] }));
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        await confirmDeletion();
      });

      it('surfaces the refusal naming the blocking digests, and claims nothing', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: `Manifest sha256:${'a1b2c3d4'.repeat(8)} was not deleted because it is indexed by other manifests: sha256:${'c3d4e5f6'.repeat(8)}.`,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('keeps the user on the page', () => {
        expect(push).not.toHaveBeenCalled();
      });

      it('releases the menu rather than leaving it pending', () => {
        expect(findActions().props('loading')).toBe(false);
      });
    });

    describe('when the delete request fails', () => {
      beforeEach(async () => {
        const deleteHandler = jest.fn().mockRejectedValue(new Error('Unavailable'));
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        await confirmDeletion();
      });

      it('raises the generic alert and claims nothing', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('keeps the user on the page', () => {
        expect(push).not.toHaveBeenCalled();
      });
    });

    describe('when it is confirmed twice while the first is in flight', () => {
      let release;
      let deleteHandler;

      beforeEach(async () => {
        deleteHandler = jest.fn().mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(mockDeleteManifestResponse());
          }),
        );
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
        findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
        await nextTick();
      });

      it('sends one mutation', () => {
        expect(deleteHandler).toHaveBeenCalledTimes(1);
      });

      it('marks the menu as pending', () => {
        expect(findActions().props('loading')).toBe(true);
      });

      describe('when the request settles', () => {
        beforeEach(async () => {
          release();
          await waitForPromises();
        });

        it('releases the menu', () => {
          expect(findActions().props('loading')).toBe(false);
        });
      });
    });

    describe('when the route moves while the delete is in flight', () => {
      let deleteHandler;

      beforeEach(async () => {
        let release;
        deleteHandler = jest.fn().mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(mockDeleteManifestResponse());
          }),
        );
        await mountLoaded({ deleteHandler });
        await openConfirmation();
        findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
        await nextTick();

        route.params = { ...route.params, artifactId: 'another-artifact-id', digest: OTHER_DIGEST };
        await nextTick();

        release();
        await waitForPromises();
      });

      it('deletes the manifest that was confirmed', () => {
        expect(deleteHandler).toHaveBeenCalledWith({
          input: { name: 'my-repository', imageId: IMAGE_ID, digest: DIGEST },
        });
      });

      it('navigates to the original version list', () => {
        expect(push).toHaveBeenCalledWith({
          name: 'artifact_versions',
          params: { id: 'my-repository', artifactId: IMAGE_ID },
        });
      });
    });
  });
});
