import { GlAlert, GlDisclosureDropdown, GlKeysetPagination, GlSkeletonLoader } from '@gitlab/ui';
import { isUndefined, omitBy } from 'lodash-es';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import detailFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql.json';
import imagesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql.json';
import packagesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql.json';
import npmPackagesFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.npm.query.graphql.json';
import upstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql.json';
import containerUpstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.container.query.graphql.json';
import statisticsFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_statistics.query.graphql.json';
import containerStatisticsFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_statistics.container.query.graphql.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective } from 'helpers/vue_mock_directive';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import BaseLayout from '~/vue_shared/components/base_layout.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from 'ee/packages_and_registries/artifact_registry/components/not_found.vue';
import {
  GRAPHQL_PAGE_SIZE,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_KIND_VIRTUAL,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  possibleTypes,
  typePolicies as artifactRegistryTypePolicies,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import getRepositoryStatisticsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_statistics.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql';
import AccessSidePanel from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/access_side_panel.vue';
import ArtifactsSection from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_section.vue';
import RepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_actions.vue';
import RepositoryDetail from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_detail.vue';
import RepositoryHeading from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_heading.vue';
import RepositorySidebar from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_sidebar.vue';
import SetupDrawer from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/setup_drawer.vue';
import UpstreamRepositoriesEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repositories_empty_state.vue';
import UpstreamRepositoriesTable from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repositories_table.vue';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import { isContainerFormat } from 'ee/packages_and_registries/artifact_registry/utils';
import {
  BASE_PATH,
  CLIENT_BASE_URL,
  FIRST_PAGE_END_CURSOR,
  ORGANIZATION_GID,
  SECOND_PAGE_START_CURSOR,
  SLUG,
  REPOSITORY_ID,
  mockDeniedRepositoryPermissions,
  mockEmptyImagePage,
  mockFirstImagePage,
  mockFullUpstreamRepositories,
  mockImagePage,
  mockRemoteSettings,
  mockRepository,
  mockRepositoryPermissions,
  mockSecondImagePage,
} from '../../mock_data';

Vue.use(VueApollo);

const REPOSITORY_NAME = mockRepository.name;

// From the generated fixture rather than a transcription of it, so a change to the schema's
// field set fails here rather than drifting. The format is overridden per example, because it
// decides which artifact connection the page then reads, and the kind because it decides the
// shape the table renders that connection in.
const serverRepository = (format = 'MAVEN', kind = REPOSITORY_KIND_HOSTED, overrides = {}) => ({
  ...detailFixture.data.organization.artifactRegistryRepository,
  format,
  kind,
  ...overrides,
});

const organizationResponse = (repository) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistryRepository: repository,
    },
  },
});

const serverImagePage = imagesFixture.data.organization.artifactRegistryRepository.images;

const serverPackagePage = packagesFixture.data.organization.artifactRegistryRepository.packages;

const serverNpmPackagePage =
  npmPackagesFixture.data.organization.artifactRegistryRepository.packages;

const serverUpstreamList =
  upstreamFixture.data.organization.artifactRegistryRepository.upstreamRepositories;

const serverContainerUpstreamList =
  containerUpstreamFixture.data.organization.artifactRegistryRepository.upstreamRepositories;

const statisticsRepository = statisticsFixture.data.organization.artifactRegistryRepository;

const serverStatistics = statisticsRepository.statistics;

const serverContainerStatistics =
  containerStatisticsFixture.data.organization.artifactRegistryRepository.statistics;

const statisticsResponse = (statistics, name = REPOSITORY_NAME) =>
  organizationResponse({ ...statisticsRepository, name, statistics });

const statisticsRepositoryHandler = (statistics = serverStatistics) =>
  jest.fn(({ name }) => statisticsResponse(statistics, name));

const ARTIFACT_CONNECTION = {
  DOCKER: serverImagePage,
  OCI: serverImagePage,
  MAVEN: serverPackagePage,
  NPM: serverNpmPackagePage,
};

// Echoes the name it was asked for, which makes the repository a read addresses legible.
const artifactRepositoryHandler = (format, connection = ARTIFACT_CONNECTION[format]) =>
  jest.fn(({ name }) =>
    organizationResponse({
      __typename: 'ArtifactRegistryRepositoryDetails',
      id: REPOSITORY_ID,
      name,
      format,
      ...(isContainerFormat(format) ? { images: connection } : { packages: connection }),
    }),
  );

const upstreamRepositoryHandler = (
  kind = REPOSITORY_KIND_VIRTUAL,
  upstreamRepositories = serverUpstreamList,
) =>
  jest.fn(({ name }) =>
    organizationResponse({
      __typename: 'ArtifactRegistryRepositoryDetails',
      id: REPOSITORY_ID,
      name,
      kind,
      upstreamRepositories,
    }),
  );

describe('ArtifactRegistryRepositoryDetail', () => {
  let wrapper;
  let router;
  let mockApollo;

  const findHeaderSkeleton = () => wrapper.findComponent(GlSkeletonLoader);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findNotFound = () => wrapper.findComponent(NotFound);
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findName = () => wrapper.findByTestId('repository-name');
  const findSetupButton = () => wrapper.findByTestId('setup-instructions');
  const findMainColumn = () => wrapper.findByTestId('detail-layout-content');
  const findSidebar = () => wrapper.findByTestId('detail-layout-sidebar');
  const findArtifactsSection = () => wrapper.findComponent(ArtifactsSection);
  const findSidebarComponent = () => wrapper.findComponent(RepositorySidebar);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findAnnouncement = () => wrapper.findByTestId('artifacts-announcement');

  // A variable the page leaves out arrives as an absent key, and one it passes as undefined as
  // a key holding undefined. Dropping those makes both comparable whole, so an unexpected
  // variable or argument fails rather than passing a partial match.
  const lastQueryVariables = (handler) => omitBy(handler.mock.calls.at(-1)[0], isUndefined);

  const createComponent = async ({
    format = 'MAVEN',
    kind = REPOSITORY_KIND_HOSTED,
    connection = ARTIFACT_CONNECTION[format],
    detailHandler = jest
      .fn()
      .mockResolvedValue(organizationResponse(serverRepository(format, kind))),
    artifactHandler = artifactRepositoryHandler(format, connection),
    upstreamRepositories = serverUpstreamList,
    upstreamHandler = upstreamRepositoryHandler(kind, upstreamRepositories),
    statisticsHandler = statisticsRepositoryHandler(
      isContainerFormat(format) ? serverContainerStatistics : serverStatistics,
    ),
    path = `/${REPOSITORY_NAME}`,
    query = {},
    provide = {},
    mountFn = shallowMountExtended,
    stubs = {},
    attachTo,
  } = {}) => {
    router = createRouter(BASE_PATH);
    await router.push({ path, query });

    mockApollo = createMockApollo(
      [
        [getRepositoryDetailQuery, detailHandler],
        [getRepositoryImagesQuery, artifactHandler],
        [getRepositoryPackagesQuery, artifactHandler],
        [getRepositoryUpstreamRepositoriesQuery, upstreamHandler],
        [getRepositoryStatisticsQuery, statisticsHandler],
      ],
      {},
      // The mock cache is built from whatever options it is handed rather than from a merge,
      // so passing the view's own policies alone would drop every global one. Handing it the
      // view's connection policy puts the cursor-agnostic cache key under test.
      {
        possibleTypes,
        typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
      },
    );

    wrapper = mountFn(RepositoryDetail, {
      router,
      apolloProvider: mockApollo,
      provide: {
        organizationGid: ORGANIZATION_GID,
        slug: SLUG,
        clientBaseUrl: CLIENT_BASE_URL,
        ...provide,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      stubs: { BaseLayout, DetailLayout, PageHeading, RepositoryHeading, ...stubs },
      attachTo,
    });

    await nextTick();
  };

  const createResolvedComponent = async (options) => {
    await createComponent(options);
    await waitForPromises();
  };

  it('reads the repository the route names, so a shared URL opens that repository', async () => {
    const detailHandler = jest
      .fn()
      .mockResolvedValue(organizationResponse(serverRepository('MAVEN')));

    await createResolvedComponent({ detailHandler, path: '/payment-core' });

    expect(lastQueryVariables(detailHandler)).toStrictEqual({
      organizationId: ORGANIZATION_GID,
      name: 'payment-core',
    });
  });

  describe('while the detail query is in flight', () => {
    beforeEach(async () => {
      await createComponent({ detailHandler: jest.fn().mockReturnValue(new Promise(() => {})) });
    });

    it('renders the header skeleton, so the page reads as the shape it is about to be', () => {
      expect(findHeaderSkeleton().exists()).toBe(true);
    });

    it('renders no heading, because there is nothing yet to name the repository with', () => {
      expect(findHeading().exists()).toBe(false);
    });

    it('renders neither page region, so an in-flight query is not mistaken for a result', () => {
      expect(findMainColumn().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
    });

    it('renders neither the not-found state nor an error', () => {
      expect(findNotFound().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the repository loads', () => {
    beforeEach(async () => {
      await createResolvedComponent();
    });

    it('lays out the main column and the sidebar the page regions fill', () => {
      expect(findMainColumn().exists()).toBe(true);
      expect(findSidebar().exists()).toBe(true);
    });

    it('names the page after the repository the read resolved', () => {
      expect(findName().text()).toBe(REPOSITORY_NAME);
    });

    it('hands the sidebar the same repository, so the two cannot disagree', () => {
      expect(findSidebarComponent().props('repository')).toEqual(serverRepository());
    });

    it('hands the sidebar the verdicts the read resolved', () => {
      expect(findSidebarComponent().props('permissions')).toEqual(
        serverRepository().userPermissions,
      );
    });

    it('renders the sidebar inside the sidebar column, not loose on the page', () => {
      expect(findSidebar().findComponent(RepositorySidebar).exists()).toBe(true);
    });

    it('renders no loading affordance, not-found state, or error', () => {
      expect(findHeaderSkeleton().exists()).toBe(false);
      expect(findNotFound().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('renders the artifacts section in the main column, not loose on the page', () => {
      expect(findMainColumn().findComponent(ArtifactsSection).exists()).toBe(true);
    });
  });

  describe('the header', () => {
    const findRepositoryHeading = () => wrapper.findComponent(RepositoryHeading);
    const findDescription = () => wrapper.findByTestId('repository-description');
    const findActionArea = () => wrapper.findByTestId('page-heading-actions');
    const findActions = () => findActionArea().findComponent(RepositoryActions);
    const findEditButton = () => wrapper.findByTestId('edit-repository');
    const findSetupDrawer = () => wrapper.findComponent(SetupDrawer);

    const createHeaderComponent = (overrides = {}, options = {}) => {
      const { format = 'MAVEN', kind = REPOSITORY_KIND_HOSTED } = overrides;
      const repository = serverRepository(format, kind, overrides);

      return createResolvedComponent({
        format,
        kind,
        detailHandler: jest.fn().mockResolvedValue(organizationResponse(repository)),
        mountFn: mountExtended,
        stubs: {
          ArtifactsSection: true,
          RepositoryActions: true,
          RepositorySidebar: true,
          SetupDrawer: true,
        },
        ...options,
      });
    };

    const createRemoteComponent = (overrides = {}, options = {}) =>
      createHeaderComponent(
        { kind: REPOSITORY_KIND_REMOTE, settings: mockRemoteSettings, ...overrides },
        options,
      );

    it('hands the heading the repository the read resolved', async () => {
      await createHeaderComponent();

      expect(findRepositoryHeading().props('repository')).toEqual(serverRepository());
    });

    it('renders the actions in the heading action area, not loose in the header', async () => {
      await createHeaderComponent();

      expect(findActions().exists()).toBe(true);
      expect(findActions().props('repository')).toEqual(serverRepository());
    });

    it('hands the actions the verdicts the read resolved', async () => {
      await createHeaderComponent();

      expect(findActions().props('permissions')).toEqual(serverRepository().userPermissions);
    });

    describe('the edit button', () => {
      beforeEach(async () => {
        await createHeaderComponent({ name: 'payment-core' }, { path: '/payment-core' });
      });

      it('renders in the heading action area, before the kebab', () => {
        expect(findActionArea().exists()).toBe(true);
        expect(findEditButton().exists()).toBe(true);
        expect(findEditButton().element.nextElementSibling).toBe(findActions().element);
      });

      it('links to the edit view for the repository the page names', () => {
        expect(findEditButton().attributes('href')).toBe(`${BASE_PATH}/payment-core/edit`);
      });

      it('is labelled Edit', () => {
        expect(findEditButton().text()).toBe('Edit');
      });
    });

    describe('the update verdict', () => {
      it('renders the edit button when it allows', async () => {
        await createHeaderComponent({ userPermissions: mockRepositoryPermissions() });

        expect(findEditButton().exists()).toBe(true);
      });

      describe('when it denies', () => {
        beforeEach(async () => {
          await createHeaderComponent({
            userPermissions: mockRepositoryPermissions({ updateRepository: false }),
          });
        });

        it('renders no edit button', () => {
          expect(findEditButton().exists()).toBe(false);
        });

        it('keeps the rest of the action area', () => {
          expect(findSetupButton().exists()).toBe(true);
          expect(findActions().exists()).toBe(true);
        });
      });
    });

    describe('the setup instructions button', () => {
      it.each([REPOSITORY_KIND_HOSTED, REPOSITORY_KIND_REMOTE])(
        'renders on a %s repository',
        async (kind) => {
          await createHeaderComponent({
            kind,
            settings: kind === REPOSITORY_KIND_REMOTE ? mockRemoteSettings : null,
          });

          expect(findSetupButton().exists()).toBe(true);
          expect(findSetupButton().text()).toBe('Setup instructions');
        },
      );

      it('is left out when no client base URL is provided, the rest of the header intact', async () => {
        await createHeaderComponent({}, { provide: { clientBaseUrl: null } });

        expect(findSetupButton().exists()).toBe(false);
        expect(findEditButton().exists()).toBe(true);
      });

      describe('when the repository holds no artifacts', () => {
        it('is left out on a hosted repository, whose empty state carries the steps inline', async () => {
          await createHeaderComponent(
            { format: 'DOCKER', kind: REPOSITORY_KIND_HOSTED },
            { connection: mockEmptyImagePage },
          );

          expect(findSetupButton().exists()).toBe(false);
          expect(findEditButton().exists()).toBe(true);
        });

        it('is left out on a remote repository, whose empty state carries the steps inline', async () => {
          await createRemoteComponent({ format: 'DOCKER' }, { connection: mockEmptyImagePage });

          expect(findSetupButton().exists()).toBe(false);
        });
      });

      it('stays on a hosted repository that holds artifacts', async () => {
        await createHeaderComponent({ kind: REPOSITORY_KIND_HOSTED });

        expect(findSetupButton().exists()).toBe(true);
      });

      describe('the drawer it owns', () => {
        beforeEach(async () => {
          await createRemoteComponent({ format: 'NPM' });
        });

        it('hands the drawer the repository it instructs for', () => {
          expect(findSetupDrawer().props()).toMatchObject({
            name: REPOSITORY_NAME,
            format: 'NPM',
            kind: REPOSITORY_KIND_REMOTE,
          });
        });

        it('stays closed until the button is pressed', () => {
          expect(findSetupDrawer().props('open')).toBe(false);
        });

        it('opens when the button is pressed', async () => {
          await findSetupButton().trigger('click');

          expect(findSetupDrawer().props('open')).toBe(true);
        });

        it('closes again when the drawer reports it was dismissed', async () => {
          await findSetupButton().trigger('click');

          findSetupDrawer().vm.$emit('close');
          await nextTick();

          expect(findSetupDrawer().props('open')).toBe(false);
        });
      });
    });

    describe('the access panel', () => {
      const findAccessPanel = () => wrapper.findComponent(AccessSidePanel);
      const findActionsToggle = () =>
        findActions().findComponent(GlDisclosureDropdown).find('button').element;

      beforeEach(async () => {
        await createHeaderComponent(
          { name: 'payment-core' },
          {
            path: '/payment-core',
            attachTo: document.body,
            stubs: {
              AccessSidePanel: true,
              ArtifactsSection: true,
              RepositorySidebar: true,
              SetupDrawer: true,
            },
          },
        );
      });

      it('hands the panel the repository it manages access for', () => {
        expect(findAccessPanel().props()).toMatchObject({
          repositoryId: detailFixture.data.organization.artifactRegistryRepository.id,
          repositoryName: 'payment-core',
        });
      });

      it('stays closed until the kebab asks for it', () => {
        expect(findAccessPanel().props('open')).toBe(false);
      });

      it('opens when the kebab asks for it', async () => {
        findActions().vm.$emit('manage-access');
        await nextTick();

        expect(findAccessPanel().props('open')).toBe(true);
      });

      describe('when the panel reports it was closed', () => {
        beforeEach(async () => {
          findActions().vm.$emit('manage-access');
          await nextTick();

          findAccessPanel().vm.$emit('close');
          await nextTick();
        });

        it('closes the panel', () => {
          expect(findAccessPanel().props('open')).toBe(false);
        });

        it('returns focus to the kebab toggle', () => {
          expect(findActionsToggle()).not.toBeNull();
          expect(document.activeElement).toBe(findActionsToggle());
        });
      });
    });

    describe('choosing Manage access from the kebab', () => {
      let portalTarget;
      let toggleFocus;

      const findPanel = () => document.querySelector('[data-testid="access-side-panel"]');

      const chooseManageAccess = async () => {
        const toggle = findActions().findComponent(GlDisclosureDropdown).find('button');
        await toggle.trigger('click');
        await waitForPromises();
        toggleFocus = jest.spyOn(toggle.element, 'focus');

        const item = findActions().find('[data-testid="manage-access"] button').element;
        item.focus();
        // Vue 3 ignores a bubbled event stamped in the same millisecond its listener was attached,
        // and open and click happen in the same millisecond here
        const dateNowSpy = jest.spyOn(Date, 'now').mockReturnValue(Date.now() + 1);
        item.click();
        dateNowSpy.mockRestore();
        await waitForPromises();
      };

      beforeEach(async () => {
        portalTarget = document.createElement('div');
        portalTarget.id = 'contextual-panel-portal';
        document.body.appendChild(portalTarget);

        await createHeaderComponent(
          { name: 'payment-core' },
          {
            path: '/payment-core',
            attachTo: document.body,
            provide: { glFeatures: { artifactRegistryRepositoryRoleManagementUi: true } },
            stubs: { ArtifactsSection: true, RepositorySidebar: true, SetupDrawer: true },
          },
        );

        await chooseManageAccess();
      });

      afterEach(() => {
        portalTarget.remove();
      });

      it('moves focus into the panel after the dropdown returns focus to its toggle', () => {
        expect(toggleFocus).toHaveBeenCalled();
        expect(findPanel()).not.toBeNull();
        expect(document.activeElement).toBe(findPanel());
      });

      it('moves focus back into the open panel when chosen again', async () => {
        await chooseManageAccess();

        expect(toggleFocus).toHaveBeenCalled();
        expect(document.activeElement).toBe(findPanel());
      });
    });

    describe('the description', () => {
      it('renders the repository description', async () => {
        await createHeaderComponent({ description: 'Artifacts for the payments monorepo' });

        expect(findDescription().text()).toBe('Artifacts for the payments monorepo');
      });

      it('is left out when the repository has none, and the rest of the header still renders', async () => {
        await createHeaderComponent({ description: null });

        expect(findDescription().exists()).toBe(false);
        expect(findName().exists()).toBe(true);
      });
    });
  });

  describe('the artifact connection', () => {
    it.each(['DOCKER', 'OCI', 'MAVEN', 'NPM'])(
      'hands the section a %s repository’s own artifacts',
      async (format) => {
        await createResolvedComponent({ format });

        expect(findArtifactsSection().props()).toEqual({
          name: REPOSITORY_NAME,
          format,
          kind: REPOSITORY_KIND_HOSTED,
          artifacts: ARTIFACT_CONNECTION[format].nodes,
          loading: false,
          hasError: false,
          permissions: serverRepository().userPermissions,
        });
      },
    );

    // The kind arrives on the detail read rather than on the artifact one, so the page is what
    // carries it across to the table.
    it('hands the section the kind the repository read returned', async () => {
      await createResolvedComponent({ kind: REPOSITORY_KIND_REMOTE });

      expect(findArtifactsSection().props('kind')).toBe(REPOSITORY_KIND_REMOTE);
    });

    it('renders the not-found state for a null connection, not the table-region alert', async () => {
      await createResolvedComponent({ format: 'DOCKER', connection: null });

      expect(findNotFound().exists()).toBe(true);
      expect(findHeading().exists()).toBe(false);
      expect(findArtifactsSection().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('asks the server for the repository the route names, so the page addresses one throughout', async () => {
      const artifactHandler = artifactRepositoryHandler('MAVEN');

      await createResolvedComponent({ artifactHandler, path: '/payment-core' });

      expect(lastQueryVariables(artifactHandler)).toStrictEqual({
        organizationId: ORGANIZATION_GID,
        name: 'payment-core',
        first: GRAPHQL_PAGE_SIZE,
      });
    });

    it('stops loading when the artifact read fails outright', async () => {
      await createResolvedComponent({
        artifactHandler: jest.fn().mockRejectedValue(new Error('Artifact Registry is down')),
      });

      expect(findArtifactsSection().props()).toMatchObject({ hasError: true, loading: false });
      expect(findHeading().exists()).toBe(true);
      expect(findSidebar().exists()).toBe(true);
    });
  });

  // The document to issue follows the repository's format, so reading before the format has
  // landed would issue the packages document for a container repository and then swap it.
  describe('before the repository has resolved', () => {
    it('issues no artifact read while the repository read is still in flight', async () => {
      const artifactHandler = artifactRepositoryHandler('MAVEN');

      await createResolvedComponent({
        artifactHandler,
        detailHandler: jest.fn().mockReturnValue(new Promise(() => {})),
      });

      expect(artifactHandler).not.toHaveBeenCalled();
    });

    it('issues no artifact read for a repository that resolved null', async () => {
      const artifactHandler = artifactRepositoryHandler('MAVEN');

      await createResolvedComponent({
        artifactHandler,
        detailHandler: jest.fn().mockResolvedValue(organizationResponse(null)),
      });

      expect(artifactHandler).not.toHaveBeenCalled();
    });

    it('reads a container repository once, on the document its format names', async () => {
      const artifactHandler = artifactRepositoryHandler('DOCKER');

      await createResolvedComponent({ format: 'DOCKER', artifactHandler });

      expect(artifactHandler).toHaveBeenCalledTimes(1);
      expect(findArtifactsSection().props('artifacts')).toEqual(serverImagePage.nodes);
    });
  });

  describe('when the artifact connection comes back empty', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        format: 'DOCKER',
        connection: mockEmptyImagePage,
      });
    });

    it('hides the sidebar stats even though the buffered count says otherwise', () => {
      expect(findSidebarComponent().props('repository').artifactsCount).not.toBe('0');
      expect(findSidebarComponent().props('hideStats')).toBe(true);
    });

    it('drops the setup button, because the empty state carries the steps inline', () => {
      expect(findSetupButton().exists()).toBe(false);
    });

    it('keeps the sidebar itself, which still carries the timestamps', () => {
      expect(findSidebar().exists()).toBe(true);
    });

    it('hands the section an empty page, so it shows the empty state', () => {
      expect(findArtifactsSection().props()).toMatchObject({
        artifacts: [],
        loading: false,
        hasError: false,
      });
    });

    it('renders no upstream empty state, which belongs to a virtual repository', () => {
      expect(wrapper.findComponent(UpstreamRepositoriesEmptyState).exists()).toBe(false);
    });
  });

  describe('when a hosted repository is empty', () => {
    it('hides the whole stats block, the figure included, whatever its statistics read returns', async () => {
      await createResolvedComponent({
        format: 'DOCKER',
        connection: mockEmptyImagePage,
        statisticsHandler: statisticsRepositoryHandler(serverContainerStatistics),
      });

      expect(findSidebarComponent().props('hideStats')).toBe(true);
    });
  });

  describe('the artifact pager', () => {
    // The request after the first page's end cursor answers the second page; every other
    // request answers the first, including the walk back from the second page's start cursor.
    const pagedArtifactHandler = () =>
      jest.fn(({ name, after }) =>
        organizationResponse({
          __typename: 'ArtifactRegistryRepositoryDetails',
          id: REPOSITORY_ID,
          name,
          format: 'DOCKER',
          images: after === FIRST_PAGE_END_CURSOR ? mockSecondImagePage : mockFirstImagePage,
        }),
      );

    const pagedComponent = (options = {}) =>
      createResolvedComponent({
        format: 'DOCKER',
        artifactHandler: pagedArtifactHandler(),
        ...options,
      });

    const renderedNames = () =>
      findArtifactsSection()
        .props('artifacts')
        .map(({ name }) => name);

    const namesOf = ({ nodes }) => nodes.map(({ name }) => name);

    const pageTo = async (query) => {
      await router.push({ query });
      await waitForPromises();
    };

    it('drives the pager from the page info the connection returns', async () => {
      await pagedComponent();

      expect(findPagination().props()).toMatchObject({
        hasNextPage: true,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: FIRST_PAGE_END_CURSOR,
      });
    });

    it('hands the pager no page either way for a single-page connection, which hides it', async () => {
      await createResolvedComponent({ format: 'DOCKER', connection: mockImagePage });

      expect(findPagination().props()).toMatchObject({
        hasNextPage: false,
        hasPreviousPage: false,
      });
    });

    it('renders the pager below the artifact section, inside the main column', async () => {
      await pagedComponent();

      expect(findMainColumn().findComponent(GlKeysetPagination).exists()).toBe(true);
    });

    it('writes the end cursor to the route query, so a page is shareable and survives a reload', async () => {
      await pagedComponent();

      findPagination().vm.$emit('next', FIRST_PAGE_END_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({ after: FIRST_PAGE_END_CURSOR });
    });

    it('clears the cursor pointing the other way, so the page just asked for is the one read', async () => {
      await pagedComponent();
      await pageTo({ after: FIRST_PAGE_END_CURSOR });

      findPagination().vm.$emit('prev', SECOND_PAGE_START_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({ before: SECOND_PAGE_START_CURSOR });
    });

    it('leaves query parameters it does not own alone', async () => {
      await pagedComponent({ query: { search: 'payment' } });

      findPagination().vm.$emit('next', FIRST_PAGE_END_CURSOR);
      await waitForPromises();

      expect(router.currentRoute.query).toEqual({
        search: 'payment',
        after: FIRST_PAGE_END_CURSOR,
      });
    });

    it.each`
      page          | query                                   | pageVariables
      ${'first'}    | ${{}}                                   | ${{ first: GRAPHQL_PAGE_SIZE }}
      ${'next'}     | ${{ after: FIRST_PAGE_END_CURSOR }}     | ${{ first: GRAPHQL_PAGE_SIZE, after: FIRST_PAGE_END_CURSOR }}
      ${'previous'} | ${{ before: SECOND_PAGE_START_CURSOR }} | ${{ last: GRAPHQL_PAGE_SIZE, before: SECOND_PAGE_START_CURSOR }}
    `(
      'asks the server for the $page page the route query names',
      async ({ query, pageVariables }) => {
        const artifactHandler = pagedArtifactHandler();

        await pagedComponent({ artifactHandler, query });

        expect(lastQueryVariables(artifactHandler)).toStrictEqual({
          organizationId: ORGANIZATION_GID,
          name: REPOSITORY_NAME,
          ...pageVariables,
        });
      },
    );

    describe('paging forward', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
      });

      it('renders the next page alone, so a page replaces the previous one rather than extending it', () => {
        expect(renderedNames()).toEqual(namesOf(mockSecondImagePage));
      });
    });

    describe('paging back', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
        await pageTo({ before: SECOND_PAGE_START_CURSOR });
      });

      it('renders the first page again', () => {
        expect(renderedNames()).toEqual(namesOf(mockFirstImagePage));
      });
    });

    describe('returning to a cursor already visited', () => {
      beforeEach(async () => {
        await pagedComponent();
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
        await pageTo({ before: SECOND_PAGE_START_CURSOR });
        await pageTo({ after: FIRST_PAGE_END_CURSOR });
      });

      it('renders the second page rather than the entry the cursor already held', () => {
        expect(renderedNames()).toEqual(namesOf(mockSecondImagePage));
      });
    });
  });

  describe('the artifact live region', () => {
    it('announces the page once it has arrived', async () => {
      await createResolvedComponent();

      expect(findAnnouncement().text()).toBe('Artifact list updated.');
    });

    it('is polite and read whole, so a page change does not interrupt mid-sentence', async () => {
      await createResolvedComponent();

      expect(findAnnouncement().attributes()).toMatchObject({
        'aria-live': 'polite',
        'aria-atomic': 'true',
      });
    });

    it('announces again on a page change, so an unchanged message still reaches a reader', async () => {
      await createResolvedComponent({
        format: 'DOCKER',
        artifactHandler: jest.fn(({ name, after }) =>
          organizationResponse({
            __typename: 'ArtifactRegistryRepositoryDetails',
            id: REPOSITORY_ID,
            name,
            format: 'DOCKER',
            images: after ? mockSecondImagePage : mockFirstImagePage,
          }),
        ),
      });

      expect(findAnnouncement().text()).toBe('Artifact list updated.');

      await router.push({ query: { after: FIRST_PAGE_END_CURSOR } });
      await nextTick();

      // A live region reads what changed, so a page landing in the same result state
      // needs the message to leave before it comes back.
      expect(findAnnouncement().text()).not.toBe('Artifact list updated.');

      await waitForPromises();

      expect(findAnnouncement().text()).toBe('Artifact list updated.');
    });

    it('does not render before the kind is known, so a virtual page makes no artifact announcement', async () => {
      await createComponent({ detailHandler: jest.fn().mockReturnValue(new Promise(() => {})) });

      expect(findAnnouncement().exists()).toBe(false);
    });

    it('says the artifacts are loading once the kind is known, before the first page arrives', async () => {
      await createResolvedComponent({
        artifactHandler: jest.fn().mockReturnValue(new Promise(() => {})),
      });

      expect(findAnnouncement().text()).toBe('Loading artifacts.');
    });
  });

  describe('when the sidebar stats stay', () => {
    it('shows them for a populated repository', async () => {
      await createResolvedComponent();

      expect(findSidebarComponent().props('hideStats')).toBe(false);
      expect(findSetupButton().exists()).toBe(true);
    });

    it('shows them when the connection failed, which says nothing about the counts', async () => {
      await createResolvedComponent({
        artifactHandler: jest.fn().mockRejectedValue(new Error('Artifact Registry is down')),
      });

      expect(findSidebarComponent().props('hideStats')).toBe(false);
    });

    it('keeps them and the setup button while a later page is in flight', async () => {
      const artifactHandler = jest
        .fn()
        .mockResolvedValueOnce(
          organizationResponse({
            __typename: 'ArtifactRegistryRepositoryDetails',
            id: REPOSITORY_ID,
            name: REPOSITORY_NAME,
            format: 'DOCKER',
            images: mockFirstImagePage,
          }),
        )
        .mockReturnValue(new Promise(() => {}));
      await createResolvedComponent({ format: 'DOCKER', artifactHandler });

      await router.push({ query: { after: FIRST_PAGE_END_CURSOR } });
      await waitForPromises();

      expect(artifactHandler).toHaveBeenCalledTimes(2);
      expect(findSidebarComponent().props('hideStats')).toBe(false);
      expect(findSetupButton().exists()).toBe(true);
    });
  });

  describe('while the first artifact page is in flight', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        artifactHandler: jest.fn().mockReturnValue(new Promise(() => {})),
      });
    });

    it('hides the sidebar stats until the page arrives', () => {
      expect(findArtifactsSection().props('loading')).toBe(true);
      expect(findSidebarComponent().props('hideStats')).toBe(true);
    });

    it('hides the setup button until the page arrives', () => {
      expect(findSetupButton().exists()).toBe(false);
    });
  });

  describe('a virtual repository', () => {
    const findUpstreamTable = () => wrapper.findComponent(UpstreamRepositoriesTable);
    const findUpstreamEmptyState = () => wrapper.findComponent(UpstreamRepositoriesEmptyState);
    const findUpstreamSkeleton = () => wrapper.findByTestId('upstream-repositories-skeleton');
    const findUpstreamError = () => wrapper.findByTestId('upstream-repositories-error');

    const createVirtualComponent = (options = {}) =>
      createResolvedComponent({ kind: REPOSITORY_KIND_VIRTUAL, ...options });

    it('reads the upstream list for the repository the route names', async () => {
      const upstreamHandler = upstreamRepositoryHandler();

      await createVirtualComponent({ upstreamHandler });

      expect(lastQueryVariables(upstreamHandler)).toStrictEqual({
        organizationId: ORGANIZATION_GID,
        name: REPOSITORY_NAME,
      });
    });

    it('issues no artifact read, because a virtual repository holds no artifacts', async () => {
      const artifactHandler = artifactRepositoryHandler('MAVEN');

      await createVirtualComponent({ artifactHandler });

      expect(artifactHandler).not.toHaveBeenCalled();
    });

    it('renders the upstream table in the main column, not loose on the page', async () => {
      await createVirtualComponent();

      expect(findMainColumn().findComponent(UpstreamRepositoriesTable).exists()).toBe(true);
    });

    it('renders no artifact section and no pager', async () => {
      await createVirtualComponent();

      expect(findArtifactsSection().exists()).toBe(false);
      expect(findPagination().exists()).toBe(false);
    });

    it('renders no artifact live region, which would announce a read this kind never issues', async () => {
      await createVirtualComponent();

      expect(findAnnouncement().exists()).toBe(false);
    });

    it('keeps the header and the sidebar, which are kind-independent', async () => {
      await createVirtualComponent();

      expect(findName().text()).toBe(REPOSITORY_NAME);
      expect(findSidebar().exists()).toBe(true);
    });

    it('renders the sidebar whole, not just its slot', async () => {
      await createVirtualComponent({ mountFn: mountExtended });

      expect(wrapper.findByTestId('repository-created').text()).toContain('Created on');
      expect(wrapper.findComponent(UpstreamRepositoriesTable).exists()).toBe(true);
    });

    describe('with upstreams to show', () => {
      beforeEach(async () => {
        await createVirtualComponent();
      });

      it('keeps the sidebar stats, the way a populated page of any kind does', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(false);
      });

      it('hands the sidebar the upstream count, the figure it renders on this kind', () => {
        expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBe(3);
      });

      it('keeps the setup button, because a client pulls through the virtual URL', () => {
        expect(findSetupButton().exists()).toBe(true);
      });

      it('instructs for the virtual repository itself, so the drawer drops Publish', () => {
        expect(wrapper.findComponent(SetupDrawer).props()).toMatchObject({
          name: REPOSITORY_NAME,
          kind: REPOSITORY_KIND_VIRTUAL,
        });
      });
    });

    describe.each([
      ['MAVEN', serverUpstreamList],
      ['NPM', serverUpstreamList],
      ['DOCKER', serverContainerUpstreamList],
      ['OCI', serverContainerUpstreamList],
    ])('of %s format', (format, upstreamRepositories) => {
      beforeEach(async () => {
        await createVirtualComponent({ format, upstreamRepositories });
      });

      it('hands the table the upstream list in the order it arrived', () => {
        expect(findUpstreamTable().props('upstreamRepositories')).toEqual(upstreamRepositories);
      });

      it('renders no artifact section', () => {
        expect(findArtifactsSection().exists()).toBe(false);
      });
    });

    it('reads no format on an upstream, because nothing on the page renders one', async () => {
      await createVirtualComponent({
        format: 'DOCKER',
        upstreamRepositories: serverContainerUpstreamList,
      });

      const summaries = findUpstreamTable()
        .props('upstreamRepositories')
        .map(({ upstreamRepository }) => Object.keys(upstreamRepository).sort());

      expect(summaries).toEqual([
        ['__typename', 'id', 'kind', 'name', 'settings', 'sizeBytes', 'userPermissions'],
        ['__typename', 'id', 'kind', 'name', 'settings', 'sizeBytes', 'userPermissions'],
      ]);
    });

    it('hands the table a full 20-upstream list whole, because the list is unpaginated', async () => {
      await createVirtualComponent({ upstreamRepositories: mockFullUpstreamRepositories });

      expect(findUpstreamTable().props('upstreamRepositories')).toHaveLength(20);
      expect(findPagination().exists()).toBe(false);
    });

    it('counts the whole list for the sidebar figure, not the buffered artifact count', async () => {
      await createVirtualComponent({ upstreamRepositories: mockFullUpstreamRepositories });

      expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBe(20);
      expect(findSidebarComponent().props('repository').artifactsCount).not.toBe('20');
    });

    describe('while the upstream list is in flight', () => {
      beforeEach(async () => {
        await createComponent({
          kind: REPOSITORY_KIND_VIRTUAL,
          upstreamHandler: jest.fn().mockReturnValue(new Promise(() => {})),
        });
        await waitForPromises();
      });

      it('renders the loading affordance in place of the table', () => {
        expect(findUpstreamSkeleton().exists()).toBe(true);
        expect(findUpstreamTable().exists()).toBe(false);
      });

      it('renders the header and the sidebar, which the repository read already answered', () => {
        expect(findName().text()).toBe(REPOSITORY_NAME);
        expect(findSidebar().exists()).toBe(true);
      });

      it('hands the sidebar a null count, so no figure renders before the list arrives', () => {
        expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBeNull();
      });

      it('hides the sidebar stats and the setup button until the list arrives', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(true);
        expect(findSetupButton().exists()).toBe(false);
      });
    });

    describe('when the upstream list comes back empty', () => {
      beforeEach(async () => {
        await createVirtualComponent({ upstreamRepositories: [] });
      });

      it('renders the empty state in place of the table', () => {
        expect(findUpstreamEmptyState().exists()).toBe(true);
        expect(findUpstreamTable().exists()).toBe(false);
      });

      it('renders no artifact section, because a virtual repository holds none', () => {
        expect(findArtifactsSection().exists()).toBe(false);
      });

      it('hides the sidebar stats, the way every kind does on an empty main region', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(true);
      });

      it('drops the setup button', () => {
        expect(findSetupButton().exists()).toBe(false);
      });
    });

    describe('the Add repository action in the empty state', () => {
      const findAddButton = () => wrapper.findByTestId('add-upstream-repository');

      const createEmptyVirtualComponent = (userPermissions = mockRepositoryPermissions()) =>
        createVirtualComponent({
          upstreamRepositories: [],
          detailHandler: jest.fn().mockResolvedValue(
            organizationResponse(
              serverRepository('MAVEN', REPOSITORY_KIND_VIRTUAL, {
                name: 'payment-core',
                userPermissions,
              }),
            ),
          ),
          path: '/payment-core',
          mountFn: mountExtended,
          stubs: { RepositoryActions: true, RepositorySidebar: true, SetupDrawer: true },
        });

      describe('when the update verdict allows', () => {
        beforeEach(async () => {
          await createEmptyVirtualComponent();
        });

        it('renders Add repository inside the empty state', () => {
          expect(
            findUpstreamEmptyState().find('[data-testid="add-upstream-repository"]').text(),
          ).toBe('Add repository');
        });

        it('links to the edit view for the repository the page names', () => {
          expect(findAddButton().attributes('href')).toBe(`${BASE_PATH}/payment-core/edit`);
        });
      });

      it('renders no Add repository when the update verdict denies', async () => {
        await createEmptyVirtualComponent(mockRepositoryPermissions({ updateRepository: false }));

        expect(findUpstreamEmptyState().exists()).toBe(true);
        expect(findAddButton().exists()).toBe(false);
      });
    });

    it('hands the table the page repository, which the row menus dissociate from', async () => {
      await createVirtualComponent();

      expect(findUpstreamTable().props('repository')).toMatchObject({
        name: 'my-repository',
        format: 'MAVEN',
      });
    });

    describe('when the upstream list resolves null', () => {
      beforeEach(async () => {
        await createVirtualComponent({ upstreamRepositories: null });
      });

      it('renders an alert naming the list, not the not-found state the repository read gets', () => {
        expect(findMainColumn().find('[data-testid="upstream-repositories-error"]').exists()).toBe(
          true,
        );
        expect(findUpstreamError().text()).toBe('Failed to load upstream repositories.');
        expect(findNotFound().exists()).toBe(false);
      });

      it('keeps the header and the sidebar, which the repository read already answered', () => {
        expect(findName().text()).toBe(REPOSITORY_NAME);
        expect(findSidebar().exists()).toBe(true);
      });

      it('renders neither the table nor the empty state, which would claim a list it never read', () => {
        expect(findUpstreamTable().exists()).toBe(false);
        expect(findUpstreamEmptyState().exists()).toBe(false);
      });

      it('hands the sidebar a null count, so it renders no figure for a list it could not read', () => {
        expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBeNull();
      });

      it('leaves hideStats off and keeps the setup button, since an unread list is not an empty one', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(false);
        expect(findSetupButton().exists()).toBe(true);
      });
    });

    describe('when the upstream list fails', () => {
      beforeEach(async () => {
        await createVirtualComponent({
          upstreamHandler: jest.fn().mockRejectedValue(new Error('Artifact Registry is down')),
        });
      });

      it('renders the service-unavailable alert in the main region', () => {
        expect(findMainColumn().find('[data-testid="upstream-repositories-error"]').exists()).toBe(
          true,
        );
        expect(findUpstreamError().text()).toBe('The Artifact Registry service is unavailable.');
      });

      it('keeps the header and the sidebar rendered', () => {
        expect(findName().text()).toBe(REPOSITORY_NAME);
        expect(findSidebar().exists()).toBe(true);
      });

      it('hands the sidebar a null count, so it renders no figure for a list it could not read', () => {
        expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBeNull();
      });

      it('renders no table and no not-found state, because the repository loaded', () => {
        expect(findUpstreamTable().exists()).toBe(false);
        expect(findNotFound().exists()).toBe(false);
      });

      it('leaves hideStats off and keeps the setup button, since a failed read is not an empty list', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(false);
        expect(findSetupButton().exists()).toBe(true);
      });
    });
  });

  describe.each([REPOSITORY_KIND_HOSTED, REPOSITORY_KIND_REMOTE])('a %s repository', (kind) => {
    it('issues no upstream read', async () => {
      const upstreamHandler = upstreamRepositoryHandler(kind);

      await createResolvedComponent({ kind, upstreamHandler });

      expect(upstreamHandler).not.toHaveBeenCalled();
    });

    it('renders the artifact section and the pager, unchanged', async () => {
      await createResolvedComponent({ kind });

      expect(findArtifactsSection().exists()).toBe(true);
      expect(findPagination().exists()).toBe(true);
      expect(wrapper.findComponent(UpstreamRepositoriesTable).exists()).toBe(false);
      expect(wrapper.findComponent(UpstreamRepositoriesEmptyState).exists()).toBe(false);
    });

    it('passes the sidebar no upstream count, so its stats stay the artifact figures', async () => {
      await createResolvedComponent({ kind });

      expect(findSidebarComponent().props('upstreamRepositoriesCount')).toBeNull();
    });
  });

  describe('the repository statistics', () => {
    const findStatsBlock = () => wrapper.findByTestId('repository-stats');
    const findStat = (name) => wrapper.findByTestId(`repository-stat-${name}`);
    const findLiveRegionTexts = () =>
      wrapper.findAll('[aria-live]').wrappers.map((region) => region.text());

    const pendingHandler = () => jest.fn().mockReturnValue(new Promise(() => {}));

    const statisticsError = () =>
      jest.fn().mockResolvedValue({
        ...statisticsResponse(null),
        errors: [{ message: 'The Artifact Registry service is unavailable.' }],
      });

    const refetchStatistics = () =>
      mockApollo.defaultClient.refetchQueries({ include: [getRepositoryStatisticsQuery] });

    // Different names would normalize onto two cache entries that keep overwriting each other.
    it('reads its fixture from the same repository as the detail fixture', () => {
      expect(statisticsRepository.name).toBe(
        detailFixture.data.organization.artifactRegistryRepository.name,
      );
    });

    const createRenderedComponent = (options = {}) =>
      createResolvedComponent({
        mountFn: mountExtended,
        stubs: { ArtifactsSection: true, RepositoryActions: true, SetupDrawer: true },
        ...options,
      });

    it('reads them once for a hosted repository, for the repository the route names', async () => {
      const statisticsHandler = statisticsRepositoryHandler();

      await createResolvedComponent({ statisticsHandler });

      expect(statisticsHandler).toHaveBeenCalledTimes(1);
      expect(lastQueryVariables(statisticsHandler)).toStrictEqual({
        organizationId: ORGANIZATION_GID,
        name: REPOSITORY_NAME,
      });
    });

    it.each([REPOSITORY_KIND_REMOTE, REPOSITORY_KIND_VIRTUAL])(
      'issues no read for a %s repository, which AR serves no statistics for, and hands the sidebar none',
      async (kind) => {
        const statisticsHandler = statisticsRepositoryHandler();

        await createResolvedComponent({ kind, statisticsHandler });

        expect(statisticsHandler).not.toHaveBeenCalled();
        expect(findSidebarComponent().props('hostedArtifactsCount')).toBeNull();
      },
    );

    it('issues no read while the repository read has yet to show the kind', async () => {
      const statisticsHandler = statisticsRepositoryHandler();

      await createResolvedComponent({ statisticsHandler, detailHandler: pendingHandler() });

      expect(statisticsHandler).not.toHaveBeenCalled();
    });

    it('issues no read for a repository that resolved null', async () => {
      const statisticsHandler = statisticsRepositoryHandler();

      await createResolvedComponent({
        statisticsHandler,
        detailHandler: jest.fn().mockResolvedValue(organizationResponse(null)),
      });

      expect(statisticsHandler).not.toHaveBeenCalled();
    });

    it.each`
      format      | statistics                   | expected
      ${'MAVEN'}  | ${serverStatistics}          | ${serverStatistics.packagesCount}
      ${'DOCKER'} | ${serverContainerStatistics} | ${serverContainerStatistics.imagesCount}
    `(
      'hands the sidebar the live count the read resolved for a hosted $format repository',
      async ({ format, statistics, expected }) => {
        await createResolvedComponent({
          format,
          statisticsHandler: statisticsRepositoryHandler(statistics),
        });

        expect(findSidebarComponent().props('hostedArtifactsCount')).toBe(expected);
      },
    );

    it.each`
      format      | expected
      ${'MAVEN'}  | ${'7'}
      ${'NPM'}    | ${'7'}
      ${'DOCKER'} | ${'2'}
      ${'OCI'}    | ${'2'}
    `(
      'picks the count of the $format family when the read carries both',
      async ({ format, expected }) => {
        await createResolvedComponent({
          format,
          statisticsHandler: statisticsRepositoryHandler({
            ...serverStatistics,
            packagesCount: '7',
            imagesCount: '2',
          }),
        });

        expect(findSidebarComponent().props('hostedArtifactsCount')).toBe(expected);
      },
    );

    it.each`
      format      | statistics
      ${'MAVEN'}  | ${{ ...serverStatistics, packagesCount: null, imagesCount: '2' }}
      ${'DOCKER'} | ${{ ...serverContainerStatistics, imagesCount: null, packagesCount: '7' }}
    `(
      'hands the sidebar no count when only the other family is set on a $format repository',
      async ({ format, statistics }) => {
        await createResolvedComponent({
          format,
          statisticsHandler: statisticsRepositoryHandler(statistics),
        });

        expect(findSidebarComponent().props('hostedArtifactsCount')).toBeNull();
      },
    );

    describe('while the read is in flight', () => {
      beforeEach(async () => {
        await createResolvedComponent({ statisticsHandler: pendingHandler() });
      });

      it('renders the header and the table without waiting on it', () => {
        expect(findName().text()).toBe(REPOSITORY_NAME);
        expect(findArtifactsSection().props()).toMatchObject({
          artifacts: serverPackagePage.nodes,
          loading: false,
        });
      });

      it('shows the stats block once the first page has arrived, handing the sidebar no count yet', () => {
        expect(findSidebarComponent().props('hideStats')).toBe(false);
        expect(findSidebarComponent().props('hostedArtifactsCount')).toBeNull();
      });
    });

    it('renders the stats block without the figure until the read answers, then the figure, announcing neither', async () => {
      let answer;
      const statisticsHandler = jest.fn().mockReturnValue(
        new Promise((resolve) => {
          answer = resolve;
        }),
      );

      await createRenderedComponent({ statisticsHandler });

      const liveRegionTexts = findLiveRegionTexts();

      expect(findStatsBlock().exists()).toBe(true);
      expect(findStat('size').exists()).toBe(true);
      expect(findStat('artifacts').exists()).toBe(false);

      answer(statisticsResponse(serverStatistics));
      await waitForPromises();

      expect(findStat('artifacts').text()).toMatchInterpolatedText('1 Package');
      expect(findLiveRegionTexts()).toEqual(liveRegionTexts);
    });

    it('re-renders the figure when a refetch answers a new count', async () => {
      const statisticsHandler = jest
        .fn()
        .mockResolvedValueOnce(statisticsResponse({ ...serverStatistics, packagesCount: '2' }))
        .mockResolvedValueOnce(statisticsResponse({ ...serverStatistics, packagesCount: '1' }));

      await createRenderedComponent({ statisticsHandler });

      expect(findStat('artifacts').text()).toMatchInterpolatedText('2 Packages');

      await refetchStatistics();
      await waitForPromises();

      expect(findStat('artifacts').text()).toMatchInterpolatedText('1 Package');
    });

    describe.each`
      outcome               | statisticsHandler
      ${'a GraphQL error'}  | ${statisticsError}
      ${'a failed request'} | ${() => jest.fn().mockRejectedValue(new Error('Artifact Registry is down'))}
    `('when the read ends in $outcome', ({ statisticsHandler }) => {
      let handler;

      beforeEach(async () => {
        handler = statisticsHandler();
        await createRenderedComponent({ statisticsHandler: handler });
      });

      it('omits the figure alone, keeping the rest of the stats block', () => {
        expect(handler).toHaveBeenCalledTimes(1);
        expect(findStat('artifacts').exists()).toBe(false);
        expect(findStat('size').exists()).toBe(true);
      });

      it('raises no alert and keeps the page out of its error state', () => {
        expect(findAlert().exists()).toBe(false);
        expect(findNotFound().exists()).toBe(false);
        expect(findName().text()).toBe(REPOSITORY_NAME);
        expect(findSidebar().exists()).toBe(true);
      });
    });

    it('clears the figure a previous read left when a re-read fails', async () => {
      const statisticsHandler = jest
        .fn()
        .mockResolvedValueOnce(statisticsResponse(serverStatistics))
        .mockRejectedValueOnce(new Error('Artifact Registry is down'));

      await createRenderedComponent({ statisticsHandler });

      expect(findStat('artifacts').text()).toMatchInterpolatedText('1 Package');

      await refetchStatistics().catch(() => {});
      await waitForPromises();

      expect(statisticsHandler).toHaveBeenCalledTimes(2);
      expect(findStat('artifacts').exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });

    it('renders the figure again when a read succeeds after a failed one', async () => {
      const statisticsHandler = jest
        .fn()
        .mockRejectedValueOnce(new Error('Artifact Registry is down'))
        .mockResolvedValueOnce(statisticsResponse(serverStatistics));

      await createRenderedComponent({ statisticsHandler });

      expect(findStat('artifacts').exists()).toBe(false);

      await refetchStatistics();
      await waitForPromises();

      expect(statisticsHandler).toHaveBeenCalledTimes(2);
      expect(findStat('artifacts').text()).toMatchInterpolatedText('1 Package');
    });
  });

  // The read resolves null both for a repository that does not exist and for one the viewer may
  // not see, so the view has one outcome to render and never tells the two apart.
  describe('when the repository resolves null', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        detailHandler: jest.fn().mockResolvedValue(organizationResponse(null)),
      });
    });

    it('renders the not-found state', () => {
      expect(findNotFound().exists()).toBe(true);
    });

    it('renders neither the heading nor a page region, so the view never confirms the repository exists', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findArtifactsSection().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
    });

    it('renders no error, because nothing failed', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when the detail query fails', () => {
    beforeEach(async () => {
      await createResolvedComponent({
        detailHandler: jest.fn().mockRejectedValue(new Error('Artifact Registry is down')),
      });
    });

    it('renders the service-unavailable alert', () => {
      expect(findAlert().text()).toBe('The Artifact Registry service is unavailable.');
    });

    it('renders no not-found state, because a failed read is not a missing repository', () => {
      expect(findNotFound().exists()).toBe(false);
    });

    it('renders neither the heading nor a page region', () => {
      expect(findHeading().exists()).toBe(false);
      expect(findArtifactsSection().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
    });
  });

  // The keyset pager holds its cursor in the route query, which re-runs this same document on
  // the mounted component, so a failed page followed by browser Back would otherwise leave
  // the alert over a page that loaded.
  describe('when a failed read is followed by a successful one', () => {
    it('renders the repository, so a recovered read is not hidden behind the old error', async () => {
      const detailHandler = jest
        .fn()
        .mockRejectedValueOnce(new Error('Artifact Registry is down'))
        .mockResolvedValue(organizationResponse(serverRepository('MAVEN')));

      await createResolvedComponent({ detailHandler, path: '/payment-core' });

      expect(findAlert().exists()).toBe(true);

      await router.push(`/${REPOSITORY_NAME}`);
      await waitForPromises();

      expect(findAlert().exists()).toBe(false);
      expect(findArtifactsSection().exists()).toBe(true);
      expect(findSidebar().exists()).toBe(true);
    });
  });

  describe('when a failed artifact read is followed by a successful one', () => {
    it('renders the artifacts, so a recovered read is not hidden behind the old error', async () => {
      const artifactHandler = artifactRepositoryHandler('MAVEN');
      artifactHandler.mockRejectedValueOnce(new Error('Artifact Registry is down'));

      await createResolvedComponent({ artifactHandler, path: '/payment-core' });

      expect(findArtifactsSection().props('hasError')).toBe(true);

      await router.push(`/${REPOSITORY_NAME}`);
      await waitForPromises();

      expect(findArtifactsSection().props()).toMatchObject({
        artifacts: serverPackagePage.nodes,
        loading: false,
        hasError: false,
      });
    });
  });

  describe('when a failed upstream read is followed by a successful one', () => {
    it('renders the table, so a recovered read is not hidden behind the old error', async () => {
      const upstreamHandler = upstreamRepositoryHandler();
      upstreamHandler.mockRejectedValueOnce(new Error('Artifact Registry is down'));

      await createResolvedComponent({
        kind: REPOSITORY_KIND_VIRTUAL,
        upstreamHandler,
        path: '/payment-core',
      });

      expect(wrapper.findByTestId('upstream-repositories-error').exists()).toBe(true);

      await router.push(`/${REPOSITORY_NAME}`);
      await waitForPromises();

      expect(wrapper.findByTestId('upstream-repositories-error').exists()).toBe(false);
      expect(wrapper.findComponent(UpstreamRepositoriesTable).exists()).toBe(true);
    });
  });

  describe('when an upstream read fails with a null list already in hand', () => {
    it('swaps the list-scoped message for the service one, so each read speaks for itself', async () => {
      const upstreamHandler = jest
        .fn()
        .mockResolvedValueOnce(
          organizationResponse({
            __typename: 'ArtifactRegistryRepositoryDetails',
            id: REPOSITORY_ID,
            name: 'payment-core',
            kind: REPOSITORY_KIND_VIRTUAL,
            upstreamRepositories: null,
          }),
        )
        .mockRejectedValue(new Error('Artifact Registry is down'));

      await createResolvedComponent({
        kind: REPOSITORY_KIND_VIRTUAL,
        upstreamHandler,
        path: '/payment-core',
      });

      expect(wrapper.findByTestId('upstream-repositories-error').text()).toBe(
        'Failed to load upstream repositories.',
      );

      await router.push(`/${REPOSITORY_NAME}`);
      await waitForPromises();

      expect(wrapper.findByTestId('upstream-repositories-error').text()).toBe(
        'The Artifact Registry service is unavailable.',
      );
      expect(findNotFound().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(true);
    });
  });

  describe('when the page is visited again in the same session', () => {
    const mountAgainst = async (apolloProvider) => {
      const localRouter = createRouter(BASE_PATH);
      await localRouter.push({ path: `/${REPOSITORY_NAME}` });

      const mounted = shallowMountExtended(RepositoryDetail, {
        router: localRouter,
        apolloProvider,
        provide: { organizationGid: ORGANIZATION_GID, slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
        stubs: { BaseLayout, DetailLayout, PageHeading, RepositoryHeading },
      });
      await waitForPromises();

      return mounted;
    };

    it('re-reads the repository from the network rather than the cache', async () => {
      const detailHandler = jest.fn().mockResolvedValue(organizationResponse(serverRepository()));
      const apolloProvider = createMockApollo(
        [
          [getRepositoryDetailQuery, detailHandler],
          [getRepositoryPackagesQuery, artifactRepositoryHandler('MAVEN')],
          [getRepositoryStatisticsQuery, statisticsRepositoryHandler()],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      );

      const first = await mountAgainst(apolloProvider);
      expect(detailHandler).toHaveBeenCalledTimes(1);
      first.destroy();

      const second = await mountAgainst(apolloProvider);
      expect(detailHandler).toHaveBeenCalledTimes(2);
      second.destroy();
    });

    // The re-read runs in the background, so the cached page has to stay on screen while it
    // is in flight rather than dropping back to the skeleton it already passed.
    it('renders the cached page at once, without a skeleton, while the re-read is in flight', async () => {
      const detailHandler = jest
        .fn()
        .mockResolvedValueOnce(organizationResponse(serverRepository()))
        .mockReturnValueOnce(new Promise(() => {}));
      const apolloProvider = createMockApollo(
        [
          [getRepositoryDetailQuery, detailHandler],
          [getRepositoryPackagesQuery, artifactRepositoryHandler('MAVEN')],
          [getRepositoryStatisticsQuery, statisticsRepositoryHandler()],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      );

      const first = await mountAgainst(apolloProvider);
      first.destroy();

      const localRouter = createRouter(BASE_PATH);
      await localRouter.push({ path: `/${REPOSITORY_NAME}` });
      const second = shallowMountExtended(RepositoryDetail, {
        router: localRouter,
        apolloProvider,
        provide: { organizationGid: ORGANIZATION_GID, slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
        stubs: { BaseLayout, DetailLayout, PageHeading, RepositoryHeading },
      });
      await nextTick();

      expect(second.findComponent(GlSkeletonLoader).exists()).toBe(false);
      expect(second.findByTestId('repository-name').text()).toBe(REPOSITORY_NAME);
      second.destroy();
    });

    it('renders the cached figure at once while the statistics re-read is in flight', async () => {
      const statisticsHandler = jest
        .fn()
        .mockResolvedValueOnce(statisticsResponse(serverStatistics))
        .mockReturnValueOnce(new Promise(() => {}));
      const apolloProvider = createMockApollo(
        [
          [
            getRepositoryDetailQuery,
            jest.fn().mockResolvedValue(organizationResponse(serverRepository())),
          ],
          [getRepositoryPackagesQuery, artifactRepositoryHandler('MAVEN')],
          [getRepositoryStatisticsQuery, statisticsHandler],
        ],
        {},
        {
          possibleTypes,
          typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies },
        },
      );

      const first = await mountAgainst(apolloProvider);
      first.destroy();

      const second = await mountAgainst(apolloProvider);

      expect(statisticsHandler).toHaveBeenCalledTimes(2);
      expect(second.findComponent(RepositorySidebar).props('hostedArtifactsCount')).toBe(
        serverStatistics.packagesCount,
      );
      second.destroy();
    });
  });

  describe('when cached removal permissions are being refreshed', () => {
    let answer;

    const repositoryWith = (deleteRepositoryUpstream) =>
      serverRepository('MAVEN', REPOSITORY_KIND_VIRTUAL, {
        userPermissions: mockRepositoryPermissions({ deleteRepositoryUpstream }),
      });
    const findRemoveItems = () => wrapper.findAllByTestId('remove-upstream-repository');

    beforeEach(async () => {
      const detailHandler = jest.fn().mockReturnValue(
        new Promise((resolve) => {
          answer = resolve;
        }),
      );
      const apolloProvider = createMockApollo(
        [
          [getRepositoryDetailQuery, detailHandler],
          [getRepositoryUpstreamRepositoriesQuery, upstreamRepositoryHandler()],
        ],
        {},
        { typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies } },
      );
      apolloProvider.clients.defaultClient.cache.writeQuery({
        query: getRepositoryDetailQuery,
        variables: { organizationId: ORGANIZATION_GID, name: REPOSITORY_NAME },
        data: organizationResponse(repositoryWith(true)).data,
      });
      router = createRouter(BASE_PATH);
      await router.push(`/${REPOSITORY_NAME}`);

      wrapper = mountExtended(RepositoryDetail, {
        router,
        apolloProvider,
        provide: { organizationGid: ORGANIZATION_GID, slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
        stubs: {
          BaseLayout,
          DetailLayout,
          PageHeading,
          RepositoryHeading,
          RepositoryActions: true,
          RepositorySidebar: true,
          SetupDrawer: true,
          GlDisclosureDropdown: true,
          GlDisclosureDropdownItem: true,
        },
      });
      await waitForPromises();
    });

    it('renders the upstream rows without removal items until the detail request finishes', () => {
      expect(wrapper.findAllByTestId('upstream-name')).toHaveLength(3);
      expect(wrapper.findAllByTestId('edit-upstream-repository')).toHaveLength(2);
      expect(findRemoveItems()).toHaveLength(0);
    });

    it.each([true, false])(
      'uses the fresh removal verdict %s once the detail request finishes',
      async (allowed) => {
        answer(organizationResponse(repositoryWith(allowed)));
        await waitForPromises();

        expect(wrapper.findAllByTestId('upstream-name')).toHaveLength(3);
        expect(findRemoveItems()).toHaveLength(allowed ? 3 : 0);
      },
    );
  });

  describe('when the cache already holds a denying verdict', () => {
    let detailHandler;
    let answer;
    let second;

    const repositoryWith = (userPermissions) => ({ ...serverRepository(), userPermissions });

    const findEditButton = () => second.findByTestId('edit-repository');
    const findSecondArtifactsSection = () => second.findComponent(ArtifactsSection);

    const mountAgainst = async (apolloProvider) => {
      const localRouter = createRouter(BASE_PATH);
      await localRouter.push({ path: `/${REPOSITORY_NAME}` });

      return shallowMountExtended(RepositoryDetail, {
        router: localRouter,
        apolloProvider,
        provide: { organizationGid: ORGANIZATION_GID, slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
        stubs: { BaseLayout, DetailLayout, PageHeading, RepositoryHeading },
      });
    };

    beforeEach(async () => {
      detailHandler = jest
        .fn()
        .mockResolvedValueOnce(
          organizationResponse(repositoryWith(mockDeniedRepositoryPermissions())),
        )
        .mockReturnValueOnce(
          new Promise((resolve) => {
            answer = resolve;
          }),
        );
      const apolloProvider = createMockApollo(
        [
          [getRepositoryDetailQuery, detailHandler],
          [getRepositoryPackagesQuery, artifactRepositoryHandler('MAVEN')],
          [getRepositoryStatisticsQuery, statisticsRepositoryHandler()],
        ],
        {},
        { typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies } },
      );

      const first = await mountAgainst(apolloProvider);
      await waitForPromises();
      first.destroy();

      second = await mountAgainst(apolloProvider);
      await nextTick();
    });

    afterEach(() => {
      second.destroy();
    });

    it('re-reads the repository from the network', () => {
      expect(detailHandler).toHaveBeenCalledTimes(2);
    });

    it('renders the cached page with no edit button while the re-read is in flight', () => {
      expect(second.findByTestId('repository-name').text()).toBe(REPOSITORY_NAME);
      expect(findEditButton().exists()).toBe(false);
    });

    it('hands the artifacts section no verdicts while the re-read is in flight', () => {
      expect(findSecondArtifactsSection().exists()).toBe(true);
      expect(findSecondArtifactsSection().props('permissions')).toBeNull();
    });

    it('hands the artifacts section the verdicts once the network answers', async () => {
      answer(organizationResponse(repositoryWith(mockRepositoryPermissions())));
      await waitForPromises();

      expect(findSecondArtifactsSection().props('permissions')).toMatchObject({
        deleteArtifact: true,
      });
    });

    it('renders the edit button once the network answer allows', async () => {
      answer(organizationResponse(repositoryWith(mockRepositoryPermissions())));
      await waitForPromises();

      expect(findEditButton().exists()).toBe(true);
    });

    it('renders no edit button when the network answer denies again', async () => {
      answer(organizationResponse(repositoryWith(mockDeniedRepositoryPermissions())));
      await waitForPromises();

      expect(findEditButton().exists()).toBe(false);
    });
  });
});
