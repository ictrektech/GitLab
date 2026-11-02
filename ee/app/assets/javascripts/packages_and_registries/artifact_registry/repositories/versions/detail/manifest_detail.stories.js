import createMockApollo from 'helpers/mock_apollo_helper';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  ARTIFACT_ID_FOR,
  CLIENT_BASE_URL,
  FIRST_PAGE_END_CURSOR,
  MANIFEST_DIGEST,
  MOCK_SIGNATURE_ARTIFACT_TYPE,
  ORGANIZATION_GID,
  SECOND_PAGE_START_CURSOR,
  SLUG,
  mockDeniedRepositoryPermissions,
  mockManifestDetails,
  mockManifestImageDetails,
  mockManifestReferrer,
  mockManifestReferrers,
  mockManifestReferrersRepository,
  mockManifestRepository,
  mockRepository,
  mockRepositoryPermissions,
  mockRepositoryResponse,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from '../../../graphql/cache_config';
import getManifestQuery from '../../../graphql/queries/get_manifest.query.graphql';
import getManifestReferrersQuery from '../../../graphql/queries/get_manifest_referrers.query.graphql';
import getRepositoryPermissionsQuery from '../../../graphql/queries/get_repository_permissions.query.graphql';
import { createRouter } from '../../../router';
import ManifestDetail from './manifest_detail.vue';

const BASE_PATH = '/o/gitlab-org/-/artifact_registry/acme/repositories';

const ARTIFACT_ID = ARTIFACT_ID_FOR.DOCKER;

const PAGE_OF_MARKERS = 'abcdefghijklmnopqrst'.split('');

const manifestHandler =
  (repository = mockManifestRepository()) =>
  () =>
    Promise.resolve(mockRepositoryResponse(repository));

const referrersHandler =
  (referrers = mockManifestReferrers()) =>
  () =>
    Promise.resolve(mockRepositoryResponse(mockManifestReferrersRepository({ referrers })));

const permissionsHandler =
  (userPermissions = mockRepositoryPermissions()) =>
  () => {
    const { __typename, id, name } = mockManifestRepository();

    return Promise.resolve(mockRepositoryResponse({ __typename, id, name, userPermissions }));
  };

const fullPageOfReferrers = (pageInfo) =>
  mockManifestReferrers(
    PAGE_OF_MARKERS.map((marker) => mockManifestReferrer({ marker })),
    pageInfo,
  );

export default {
  component: ManifestDetail,
  title:
    'ee/packages_and_registries/artifact_registry/repositories/versions/detail/manifest_detail',
};

const Template =
  ({
    handler = manifestHandler(),
    referrers = referrersHandler(),
    permissions = permissionsHandler(),
    artifactId = ARTIFACT_ID,
    digest = MANIFEST_DIGEST,
    query = {},
  } = {}) =>
  () => {
    const router = createRouter(BASE_PATH);
    // Vue Router 4 navigates asynchronously, so render only once the route has its params.
    const navigation = router.push({
      path: `/${mockRepository.name}/${artifactId}/manifests/${encodeURIComponent(digest)}`,
      query,
    });

    return {
      components: { ManifestDetail },
      router,
      data: () => ({ routeReady: false }),
      async created() {
        await navigation;
        this.routeReady = true;
      },
      apolloProvider: createMockApollo(
        [
          [getManifestQuery, handler],
          [getManifestReferrersQuery, referrers],
          [getRepositoryPermissionsQuery, permissions],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      ),
      provide: {
        breadCrumbState: {
          artifactName: '',
          manifestName: '',
          updateArtifactName() {},
          updateManifestName() {},
        },
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
      },
      template: '<manifest-detail v-if="routeReady" />',
    };
  };

const withManifest = (manifest) => manifestHandler(mockManifestRepository({ manifest }));

export const Default = Template();

export const OciIndex = Template({
  handler: manifestHandler(mockManifestRepository({ format: 'OCI' })),
});

export const ManyTags = Template({
  handler: withManifest(
    mockManifestDetails({ tags: Array.from({ length: 40 }, (_, index) => `release-${index}`) }),
  ),
});

export const LongTagName = Template({
  handler: withManifest(mockManifestDetails({ tags: ['a'.repeat(128), 'latest'] })),
});

export const UntaggedOverview = Template({
  handler: withManifest(mockManifestDetails({ tags: [] })),
});

export const SinglePlatformImage = Template({ handler: withManifest(mockManifestImageDetails()) });

export const Referrer = Template({
  handler: withManifest(
    mockManifestDetails({
      artifactType: MOCK_SIGNATURE_ARTIFACT_TYPE,
      subjectDigest: `sha256:${'b2c3d4e5'.repeat(8)}`,
      childrenCount: 0,
      children: [],
      tags: [],
      referrersCount: 0,
    }),
  ),
});

export const ReferrersTab = Template({ query: { tab: 'referrers' } });

export const ReferrersTabFirstPage = Template({
  handler: withManifest(mockManifestDetails({ referrersCount: 26 })),
  referrers: referrersHandler(
    fullPageOfReferrers({ hasNextPage: true, endCursor: FIRST_PAGE_END_CURSOR }),
  ),
  query: { tab: 'referrers' },
});

export const ReferrersTabSecondPage = Template({
  handler: withManifest(mockManifestDetails({ referrersCount: 26 })),
  referrers: referrersHandler(
    fullPageOfReferrers({ hasPreviousPage: true, startCursor: SECOND_PAGE_START_CURSOR }),
  ),
  query: { tab: 'referrers', after: FIRST_PAGE_END_CURSOR },
});

export const ReferrersTabLoading = Template({
  query: { tab: 'referrers' },
  referrers: () => new Promise(() => {}),
});

export const ReferrersTabUnavailable = Template({
  query: { tab: 'referrers' },
  referrers: () => Promise.reject(new Error('Unavailable')),
});

export const ReferrersTabNone = Template({
  handler: withManifest(mockManifestDetails({ referrersCount: 0 })),
  referrers: referrersHandler(mockManifestReferrers([])),
  query: { tab: 'referrers' },
});

export const Loading = Template({ handler: () => new Promise(() => {}) });

export const ServiceUnavailable = Template({
  handler: () => Promise.reject(new Error('Unavailable')),
});

export const NotFound = Template({ handler: () => Promise.resolve(mockRepositoryResponse(null)) });

export const ImageUnnamed = Template({
  handler: manifestHandler(mockManifestRepository({ image: null })),
});

export const ManifestNotFound = Template({ handler: withManifest(null) });

export const DeleteDenied = Template({
  permissions: permissionsHandler(mockDeniedRepositoryPermissions()),
});
