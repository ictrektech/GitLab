import {
  GlBadge,
  GlButton,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlPopover,
  GlTable,
  GlTruncate,
} from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { RouterLinkStub } from '@vue/test-utils';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { getTableHeaderLabel } from 'helpers/gl_table_helper';
import { useFakeDate } from 'helpers/fake_date';
import waitForPromises from 'helpers/wait_for_promises';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import DeleteConfirmationModal from 'ee/packages_and_registries/artifact_registry/repositories/components/delete_confirmation_modal.vue';
import ManifestsTable from 'ee/packages_and_registries/artifact_registry/repositories/versions/manifests_table.vue';
import PullCommandDrawer from 'ee/packages_and_registries/artifact_registry/repositories/versions/pull_command_drawer.vue';
import { createAlert } from '~/alert';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  CLIENT_BASE_URL,
  MOCK_RAW_ARTIFACT_TYPE,
  SLUG,
  mockDeniedRepositoryPermissions,
  mockLabelledManifests,
  mockManifests,
  mockRepository,
  mockRepositoryArtifacts,
  mockRepositoryPermissions,
} from '../../mock_data';

jest.mock('ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation');
jest.mock('~/alert');
jest.mock('~/lib/utils/copy_to_clipboard');

Vue.use(VueApollo);

const DEFAULT_SORT = { sortBy: 'createdAt', sortDesc: true };

const DOCKER_IMAGE = mockRepositoryArtifacts('DOCKER').image;

const ALL_HEADERS = [
  'Digest',
  'Type',
  'Tags',
  'Platforms',
  'Referrers',
  'Size',
  'Published',
  'Actions',
];

const manifestDetailRoute = (digest) => ({
  name: 'manifest_detail',
  params: { id: mockRepository.name, artifactId: DOCKER_IMAGE.id, digest },
});

describe('ArtifactRegistryManifestsTable', () => {
  let wrapper;
  let apolloProvider;

  const mockToast = { show: jest.fn() };

  useFakeDate(2026, 6, 15);

  const findHeaders = () => wrapper.findAll('th').wrappers.map(getTableHeaderLabel);
  const findDigestCells = () =>
    wrapper.findAllByTestId('manifest-digest').wrappers.map((cell) => cell.text());
  const findSizeCells = () =>
    wrapper.findAllByTestId('manifest-size').wrappers.map((cell) => cell.text());
  const findPublishedCells = () => wrapper.findAllComponents(TimeAgoTooltip);
  const findDigestLinks = () =>
    wrapper
      .findAllByTestId('manifest-digest')
      .wrappers.map((cell) => cell.findComponent(RouterLinkStub));
  const findSubjectLinkOf = (row) =>
    wrapper.findAllByTestId('manifest-type').at(row).findComponent(RouterLinkStub);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findMenus = () => wrapper.findAllByTestId('manifest-actions');
  const findMenuComponents = () => wrapper.findAllComponents(GlDisclosureDropdown);
  const findDeleteItems = () => wrapper.findAllByTestId('delete-manifest');
  const findDeleteItemComponents = () =>
    findDeleteItems().wrappers.map((item) => item.findComponent(GlDisclosureDropdownItem));
  const findDeleteModal = () => wrapper.findComponent(DeleteConfirmationModal);
  const findPullCommandItems = () => wrapper.findAllByTestId('view-pull-command');
  const findCopyDigestItems = () => wrapper.findAllByTestId('copy-digest');
  const findPlatformsCells = () => wrapper.findAllByTestId('manifest-platforms');
  const findReferrersCells = () => wrapper.findAllByTestId('manifest-referrers');
  const findTagBadges = () => wrapper.findAllByTestId('manifest-tag');
  const findMoreTags = () => wrapper.findByTestId('manifest-more-tags');
  const findUntaggedCells = () => wrapper.findAllByTestId('manifest-untagged');
  const findReferencedByButtons = () => wrapper.findAllByTestId('manifest-referenced-by');
  const findReferencedByPopover = () => wrapper.findComponent(GlPopover);
  const findReferencedByLinks = () => findReferencedByPopover().findAllComponents(RouterLinkStub);
  const findDigestCellOf = (row) => wrapper.findAll('tbody tr').at(row).findAll('td').at(0);
  const findDrawer = () => wrapper.findComponent(PullCommandDrawer);
  const findCloseButton = () => wrapper.find('.gl-drawer-close-button');

  // GlSprintf splices its slots with direction marks, which a text comparison would otherwise
  // read as characters of the label.
  const stripDirectionMarks = (text) => text.replace(/\u200e/g, '');

  const findTypeCell = (row) =>
    stripDirectionMarks(wrapper.findAllByTestId('manifest-type').at(row).text());
  const findReferencedByText = () =>
    stripDirectionMarks(findReferencedByPopover().text()).replace(/\s+/g, ' ');

  const chooseMenuItem = async (findItems, row) => {
    await findMenus().at(row).find('button[aria-expanded]').trigger('click');

    findItems().at(row).find('button').trigger('click');
    await waitForPromises();
  };

  const openPullCommandFor = (row) => chooseMenuItem(findPullCommandItems, row);

  const copyDigestFor = (row) => chooseMenuItem(findCopyDigestItems, row);

  const createComponent = ({
    manifests = mockManifests,
    sort = DEFAULT_SORT,
    permissions = mockRepositoryPermissions(),
    ...props
  } = {}) => {
    apolloProvider = createMockApollo();
    jest.spyOn(apolloProvider.defaultClient, 'refetchQueries').mockResolvedValue([]);

    wrapper = mountExtended(ManifestsTable, {
      propsData: {
        manifests,
        format: 'DOCKER',
        artifact: DOCKER_IMAGE,
        name: mockRepository.name,
        imageId: DOCKER_IMAGE.id,
        sort,
        permissions,
        ...props,
      },
      apolloProvider,
      mocks: { $toast: mockToast },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL },
      stubs: {
        MountingPortal: { name: 'MountingPortalStub', template: '<div><slot /></div>' },
        RouterLink: RouterLinkStub,
      },
    });
  };

  const findRefetches = () => apolloProvider.defaultClient.refetchQueries;

  describe('when a column is hidden', () => {
    it('omits it from the table', () => {
      createComponent({ hiddenColumns: ['size'] });

      expect(findHeaders()).toEqual([
        'Digest',
        'Type',
        'Tags',
        'Platforms',
        'Referrers',
        'Published',
        'Actions',
      ]);
    });
  });

  it('renders the columns an Artifact Registry manifest can fill', () => {
    createComponent();

    expect(findHeaders()).toEqual(ALL_HEADERS);
  });

  describe('the Type column', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each`
      row  | manifest                      | label
      ${0} | ${'an index'}                 | ${'Index'}
      ${1} | ${'a platform image'}         | ${'Image'}
      ${2} | ${'a cosign signature'}       | ${'Signature for 111111111111'}
      ${3} | ${'an SBOM attestation'}      | ${'SBOM attestation for 222222222222'}
      ${4} | ${'a SLSA attestation'}       | ${'SLSA attestation for 222222222222'}
      ${5} | ${'an unrecognized referrer'} | ${`${MOCK_RAW_ARTIFACT_TYPE} for 222222222222`}
      ${6} | ${'a referrer with no type'}  | ${'Referrer for 222222222222'}
    `('names $manifest by what it is, and a referrer by what it attaches to', ({ row, label }) => {
      expect(findTypeCell(row)).toBe(label);
    });

    it('renders one truncation, for the referrer that carries an artifact type to truncate', () => {
      expect(wrapper.findAllComponents(GlTruncate)).toHaveLength(1);
    });

    it('renders an unrecognized artifact type through a truncation with its full value', () => {
      const truncate = wrapper.findComponent(GlTruncate);

      expect(truncate.props('text')).toBe(MOCK_RAW_ARTIFACT_TYPE);
      expect(truncate.props('withTooltip')).toBe(true);
    });

    it('renders no truncation for a page whose every type it recognizes', () => {
      createComponent({ manifests: mockLabelledManifests });

      expect(wrapper.findComponent(GlTruncate).exists()).toBe(false);
    });

    it('links a referrer to the manifest it attaches to, by its full digest', () => {
      expect(findSubjectLinkOf(2).props('to')).toEqual(
        manifestDetailRoute(mockManifests[0].digest),
      );
      expect(findSubjectLinkOf(2).attributes('aria-label')).toBe('Manifest 111111111111');
    });

    it('renders no link for a manifest that attaches to nothing', () => {
      expect(findSubjectLinkOf(0).exists()).toBe(false);
    });
  });

  describe('the Tags column', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the tag of the index as a badge, with no count of more tags', () => {
      expect(findTagBadges()).toHaveLength(1);
      expect(findTagBadges().at(0).text()).toBe('trixie');
      expect(findMoreTags().exists()).toBe(false);
    });

    it('renders every manifest carrying no tags as untagged', () => {
      expect(findUntaggedCells().wrappers.map((cell) => cell.text())).toEqual(
        Array(mockManifests.length - 1).fill('untagged'),
      );
    });
  });

  describe('the Tags column for a single manifest', () => {
    const IMAGE = mockManifests[1];

    it('lists the previewed tags and counts the rest', () => {
      createComponent({ manifests: [{ ...IMAGE, tagsPreview: ['latest', 'v1'], tagsCount: 5 }] });

      expect(findTagBadges().wrappers.map((badge) => badge.text())).toEqual(['latest', 'v1']);
      expect(findMoreTags().text()).toBe('+3 more');
    });

    it('counts no rest for a manifest with no tag count', () => {
      createComponent({ manifests: [{ ...IMAGE, tagsPreview: ['a'], tagsCount: null }] });

      expect(findTagBadges().wrappers.map((badge) => badge.text())).toEqual(['a']);
      expect(findMoreTags().exists()).toBe(false);
    });

    it('renders a placeholder hidden from assistive technology for a manifest with no tag preview', () => {
      createComponent({ manifests: [{ ...IMAGE, tagsPreview: null }] });

      expect(findUntaggedCells().at(0).text()).toBe('—');
      expect(findUntaggedCells().at(0).attributes('aria-hidden')).toBe('true');
    });
  });

  describe('the referenced-by indicator', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders one button, in the digest cell of the image the index references', () => {
      expect(findReferencedByButtons()).toHaveLength(1);
      expect(findDigestCellOf(1).find('[data-testid="manifest-referenced-by"]').exists()).toBe(
        true,
      );
    });

    it('renders a link icon button naming the referencing manifest', () => {
      const button = findReferencedByButtons().at(0);

      expect(button.findComponent(GlButton).props('icon')).toBe('link');
      expect(button.attributes('aria-label')).toBe('Referenced by manifest 111111111111');
    });

    it('opens a popover from the button, reading as one lowercase phrase', () => {
      expect(findReferencedByPopover().props('target')).toBe(
        findReferencedByButtons().at(0).attributes('id'),
      );
      expect(findReferencedByText()).toBe('referenced by 111111111111');
    });

    it('links the referencing manifest to its detail page by short digest', () => {
      expect(findReferencedByLinks()).toHaveLength(1);
      expect(findReferencedByLinks().at(0).text()).toBe('111111111111');
      expect(findReferencedByLinks().at(0).props('to')).toEqual(
        manifestDetailRoute(mockManifests[0].digest),
      );
    });
  });

  describe('the referenced-by indicator for a manifest with several parents', () => {
    beforeEach(() => {
      createComponent({
        manifests: [
          {
            ...mockManifests[1],
            parentsPreview: [`sha256:${'1'.repeat(64)}`, `sha256:${'2'.repeat(64)}`],
          },
        ],
      });
    });

    it('names every referencing manifest on the button', () => {
      expect(findReferencedByButtons().at(0).attributes('aria-label')).toBe(
        'Referenced by manifests 111111111111, 222222222222',
      );
    });

    it('links every referencing manifest in the popover, separated by commas', () => {
      expect(
        findReferencedByLinks().wrappers.map((link) => link.props('to').params.digest),
      ).toEqual([`sha256:${'1'.repeat(64)}`, `sha256:${'2'.repeat(64)}`]);
      expect(findReferencedByText()).toBe('referenced by 111111111111, 222222222222');
    });
  });

  describe('the Platforms column', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each`
      row  | manifest                      | label            | badge
      ${0} | ${'an index'}                 | ${'3 platforms'} | ${true}
      ${1} | ${'a platform image'}         | ${'linux/amd64'} | ${false}
      ${2} | ${'a cosign signature'}       | ${'—'}           | ${false}
      ${3} | ${'an SBOM attestation'}      | ${'—'}           | ${false}
      ${4} | ${'a SLSA attestation'}       | ${'—'}           | ${false}
      ${5} | ${'an unrecognized referrer'} | ${'—'}           | ${false}
      ${6} | ${'a referrer with no type'}  | ${'—'}           | ${false}
    `('counts the platforms of $manifest as $label', ({ row, label, badge }) => {
      expect(findPlatformsCells().at(row).text()).toBe(label);
      expect(findPlatformsCells().at(row).findComponent(GlBadge).exists()).toBe(badge);
    });

    it('hides the placeholder from assistive technology, because it stands for no value', () => {
      expect(findPlatformsCells().at(2).attributes('aria-hidden')).toBe('true');
    });
  });

  describe('the Platforms column for a single manifest', () => {
    const INDEX = mockManifests[0];
    const IMAGE = mockManifests[1];

    it.each`
      manifest                           | item                                                                     | label
      ${'an image with an OS variant'}   | ${{ ...IMAGE, architecture: 'arm64', osVariant: 'v8' }}                  | ${'linux/arm64/v8'}
      ${'an index of one child'}         | ${{ ...INDEX, childrenCount: 1 }}                                        | ${'1 platform'}
      ${'an index of no children'}       | ${{ ...INDEX, childrenCount: 0 }}                                        | ${'—'}
      ${'an index counting no children'} | ${{ ...INDEX, childrenCount: null }}                                     | ${'—'}
      ${'an image naming no platform'}   | ${{ ...IMAGE, architecture: null, os: null, osVariant: null }}           | ${'—'}
      ${'a buildx attestation image'}    | ${{ ...IMAGE, architecture: 'unknown', os: 'unknown', osVariant: null }} | ${'—'}
    `('renders $manifest as $label', ({ item, label }) => {
      createComponent({ manifests: [item] });

      expect(findPlatformsCells().at(0).text()).toBe(label);
    });
  });

  describe('the Referrers column', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each`
      row  | manifest                      | label            | badge
      ${0} | ${'an index'}                 | ${'1 referrer'}  | ${true}
      ${1} | ${'a platform image'}         | ${'4 referrers'} | ${true}
      ${2} | ${'a cosign signature'}       | ${'—'}           | ${false}
      ${3} | ${'an SBOM attestation'}      | ${'—'}           | ${false}
      ${4} | ${'a SLSA attestation'}       | ${'—'}           | ${false}
      ${5} | ${'an unrecognized referrer'} | ${'—'}           | ${false}
      ${6} | ${'a referrer with no type'}  | ${'—'}           | ${false}
    `('counts what attaches to $manifest as $label', ({ row, label, badge }) => {
      expect(findReferrersCells().at(row).text()).toBe(label);
      expect(findReferrersCells().at(row).findComponent(GlBadge).exists()).toBe(badge);
    });

    it('hides the placeholder from assistive technology, because it stands for no value', () => {
      expect(findReferrersCells().at(2).attributes('aria-hidden')).toBe('true');
    });
  });

  describe('the Referrers column for a manifest with no count', () => {
    beforeEach(() => {
      createComponent({ manifests: [{ ...mockManifests[0], referrersCount: null }] });
    });

    it('renders the placeholder', () => {
      expect(findReferrersCells().at(0).text()).toBe('—');
    });
  });

  it('shortens the digest to twelve characters and drops the algorithm prefix', () => {
    createComponent();

    expect(findDigestCells()).toEqual([
      '111111111111',
      '222222222222',
      '333333333333',
      '444444444444',
      '555555555555',
      '666666666666',
      '777777777777',
    ]);
  });

  describe('the digest cell, which is the entry point to the manifest page', () => {
    beforeEach(() => createComponent());

    it('links every row to that manifest own page, under the same repository and image', () => {
      expect(findDigestLinks()[0].props('to')).toEqual(
        manifestDetailRoute(mockManifests[0].digest),
      );
      expect(findDigestLinks()).toHaveLength(mockManifests.length);
    });

    it('carries the full digest in the route rather than the shortened one it renders', () => {
      expect(findDigestLinks().map((link) => link.props('to').params.digest)).toEqual(
        mockManifests.map(({ digest }) => digest),
      );
    });

    it('names the link, since a shortened digest does not describe itself', () => {
      expect(findDigestLinks()[0].attributes('aria-label')).toBe('Manifest 111111111111');
    });
  });

  it('renders the size as a human-readable byte count', () => {
    createComponent();

    expect(findSizeCells()).toEqual([
      '3.07 MiB',
      '2.00 MiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
      '3.37 KiB',
    ]);
  });

  it('renders the publication date as a relative time', () => {
    createComponent();

    expect(findPublishedCells().wrappers.map((cell) => cell.props('time'))).toEqual(
      mockManifests.map(({ createdAt }) => createdAt),
    );
  });

  it('renders the headers with no rows for an image carrying no manifests', () => {
    createComponent({ manifests: [] });

    expect(findHeaders()).toEqual(ALL_HEADERS);
    expect(findDigestCells()).toEqual([]);
  });

  describe('the row actions menu', () => {
    beforeEach(() => createComponent());

    it('gives every row a menu offering the pull command', () => {
      expect(findMenus()).toHaveLength(mockManifests.length);
      expect(findPullCommandItems().at(0).text()).toBe('View pull command');
    });

    it('names the manifest each menu belongs to by its short digest, because its toggle renders as an icon', () => {
      expect(findMenus().at(0).text()).toContain('More actions for 111111111111');
    });

    it('offers a copy of the digest on every row, which renders only part of it', () => {
      expect(findCopyDigestItems()).toHaveLength(mockManifests.length);
      expect(findCopyDigestItems().at(0).text()).toBe('Copy digest');
    });

    describe('copying the digest', () => {
      it('copies the full canonical digest of the row it was chosen from', async () => {
        await copyDigestFor(1);

        expect(copyToClipboard).toHaveBeenCalledWith(mockManifests[1].digest);
      });

      it('reports the copy through a toast', async () => {
        copyToClipboard.mockResolvedValue();

        await copyDigestFor(1);

        expect(mockToast.show).toHaveBeenCalledWith('Digest copied to clipboard.');
      });

      it('reports a failed copy rather than claiming it succeeded', async () => {
        const error = new Error('Clipboard write failed');
        copyToClipboard.mockRejectedValue(error);
        jest.spyOn(Sentry, 'captureException');

        await copyDigestFor(1);

        expect(Sentry.captureException).toHaveBeenCalledWith(error);
        expect(mockToast.show).not.toHaveBeenCalled();
      });
    });
  });

  describe('the pull command drawer', () => {
    beforeEach(() => createComponent());

    it('stays closed until a row asks for it', () => {
      expect(findDrawer().props('open')).toBe(false);
    });

    it('opens against the row it was asked from', async () => {
      await openPullCommandFor(1);

      expect(findDrawer().props()).toMatchObject({
        open: true,
        format: 'DOCKER',
        artifact: DOCKER_IMAGE,
        name: mockRepository.name,
        digest: mockManifests[1].digest,
        tags: [],
      });
    });

    it('hands the drawer the tags of the row it was asked from', async () => {
      await openPullCommandFor(0);

      expect(findDrawer().props('tags')).toEqual(['trixie']);
      expect(wrapper.text()).toContain(
        `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service:trixie'`,
      );
    });

    it('renders that row command through the shell, not only into its props', async () => {
      await openPullCommandFor(1);

      expect(wrapper.text()).toContain(
        `docker pull 'artifact-registry.example.com/acme/container/my-repository/payment-service@${mockManifests[1].digest}'`,
      );
    });

    it('reopens against a different row rather than keeping the first', async () => {
      await openPullCommandFor(1);
      await openPullCommandFor(0);

      expect(findDrawer().props('digest')).toBe(mockManifests[0].digest);
    });

    it('closes from the drawer close button, taking the rendered command with it', async () => {
      await openPullCommandFor(0);

      await findCloseButton().trigger('click');

      expect(findDrawer().props('open')).toBe(false);
      expect(wrapper.text()).not.toContain('docker pull');
    });

    it('renders one drawer for the table rather than one per row', () => {
      expect(wrapper.findAllComponents(PullCommandDrawer)).toHaveLength(1);
    });
  });

  describe('the pull command drawer for a manifest with several tags', () => {
    it('hands the drawer every previewed tag of the row', async () => {
      createComponent({
        manifests: [{ ...mockManifests[1], tagsPreview: ['1.6.41', 'latest'], tagsCount: 2 }],
      });

      await openPullCommandFor(0);

      expect(findDrawer().props('tags')).toEqual(['1.6.41', 'latest']);
    });

    it('hands the drawer no tags for a row whose tags were not read', async () => {
      createComponent({ manifests: [{ ...mockManifests[1], tagsPreview: null }] });

      await openPullCommandFor(0);

      expect(findDrawer().props('tags')).toEqual([]);
    });
  });

  describe('sorting', () => {
    const FIELD_KEYS = [
      'digest',
      'type',
      'tags',
      'platforms',
      'referrers',
      'size',
      'createdAt',
      'actions',
    ];

    const findHeaderCells = () => wrapper.findAllByRole('columnheader');
    const findSortStates = () =>
      Object.fromEntries(
        findHeaderCells().wrappers.map((header, index) => [
          FIELD_KEYS[index],
          header.attributes('aria-sort'),
        ]),
      );
    const clickHeader = (key) => findHeaderCells().at(FIELD_KEYS.indexOf(key)).trigger('click');

    it.each([
      [false, 'ascending'],
      [true, 'descending'],
    ])('exposes the active column, reading a sortDesc of %s as %s', (sortDesc, ariaSort) => {
      createComponent({ sort: { sortBy: 'createdAt', sortDesc } });

      expect(findSortStates()).toEqual({
        digest: undefined,
        type: undefined,
        tags: undefined,
        platforms: undefined,
        referrers: undefined,
        size: undefined,
        createdAt: ariaSort,
        actions: undefined,
      });
    });

    it('asks for Published ascending when its header is clicked, leaving the row order alone', async () => {
      createComponent();

      await clickHeader('createdAt');

      expect(wrapper.emitted('sort-changed')).toEqual([[{ sortBy: 'createdAt', sortDesc: false }]]);
      expect(findDigestCells()).toHaveLength(mockManifests.length);
    });

    it('follows a sort it did not ask for, so an externally applied sort reaches the header', async () => {
      createComponent({ sort: { sortBy: 'createdAt', sortDesc: false } });

      expect(findSortStates()).toMatchObject({ createdAt: 'ascending' });

      wrapper.setProps({ sort: { sortBy: 'createdAt', sortDesc: true } });
      await nextTick();

      expect(findSortStates()).toMatchObject({ createdAt: 'descending' });
    });

    it('does not remount when the sort it asked for comes back down', async () => {
      createComponent();

      const tableBefore = wrapper.findComponent(GlTable).vm;

      await clickHeader('createdAt');
      wrapper.setProps({ sort: { sortBy: 'createdAt', sortDesc: false } });
      await nextTick();

      expect(wrapper.findComponent(GlTable).vm).toBe(tableBefore);
      expect(findSortStates()).toMatchObject({ createdAt: 'ascending' });
    });
  });
  describe('when a re-read for a new sort or page is in flight', () => {
    beforeEach(() => createComponent({ isLoading: true }));

    it('marks the table busy, so the rows it still renders are not read as the new order', () => {
      expect(wrapper.find('table').attributes('aria-busy')).toBe('true');
    });

    it('renders a loading affordance over the rows it keeps', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('when no read is in flight', () => {
    beforeEach(() => createComponent());

    it('leaves the table unbusy and renders no loading affordance', () => {
      expect(wrapper.find('table').attributes('aria-busy')).toBe('false');
      expect(findLoadingIcon().exists()).toBe(false);
    });
  });

  describe('deleting a manifest', () => {
    const index = mockManifests[0];

    const openDeleteFor = async (row) => {
      await findMenus().at(row).find('button[aria-expanded]').trigger('click');

      findDeleteItems().at(row).find('button').trigger('click');
      await nextTick();
    };

    const confirmDeletion = async () => {
      findDeleteModal().vm.$emit('confirm', findDeleteModal().props('target'));
      await waitForPromises();
    };

    beforeEach(() => {
      executeDeleteMutation.mockResolvedValue(true);
      createComponent();
    });

    it('offers a delete item on every row, marked destructive', () => {
      expect(findDeleteItemComponents()).toHaveLength(mockManifests.length);
      expect(findDeleteItemComponents()[0].props('item')).toMatchObject({
        text: 'Delete manifest',
        variant: 'danger',
      });
    });

    it('names the manifest in the menu toggle, which renders as an icon', () => {
      expect(findMenuComponents().at(0).props('toggleText')).toBe('More actions for 111111111111');
    });

    it('starts with the confirmation closed', () => {
      expect(findDeleteModal().props('target')).toBeNull();
    });

    describe('when a row is chosen', () => {
      beforeEach(async () => {
        await openDeleteFor(0);
      });

      it('opens the confirmation on that row and sends nothing', () => {
        expect(findDeleteModal().props()).toMatchObject({
          title: 'Delete manifest?',
          name: '111111111111',
          actionText: 'Delete manifest',
        });
        expect(findDeleteModal().props('target')).toMatchObject({ digest: index.digest });
        expect(executeDeleteMutation).not.toHaveBeenCalled();
      });

      it('closes again when the confirmation reports it was dismissed', async () => {
        findDeleteModal().vm.$emit('change', null);
        await nextTick();

        expect(findDeleteModal().props('target')).toBeNull();
        expect(executeDeleteMutation).not.toHaveBeenCalled();
      });
    });

    describe.each`
      row  | kind             | body
      ${0} | ${'an index'}    | ${'This action permanently deletes manifest %{name} and any tags pointing to it. Its child manifests are not deleted and will remain in Artifact Registry as untagged, standalone manifests. This action cannot be undone.'}
      ${1} | ${'an image'}    | ${'This action permanently deletes manifest %{name} and any tags pointing to it. This action cannot be undone.'}
      ${2} | ${'a signature'} | ${'This action permanently deletes signature %{name} and any tags pointing to it. The image it signs will then verify as unsigned. This action cannot be undone.'}
    `('when the chosen row is $kind', ({ row, body }) => {
      beforeEach(async () => {
        await openDeleteFor(row);
      });

      it('spells out what the delete costs for that kind', () => {
        expect(findDeleteModal().props('body')).toBe(body);
      });
    });

    describe('when the confirmation is accepted', () => {
      beforeEach(async () => {
        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('addresses the manifest by digest within its image, sending no refetch of its own', () => {
        expect(executeDeleteMutation).toHaveBeenCalledWith(expect.anything(), {
          mutation: deleteManifestMutation,
          input: {
            name: mockRepository.name,
            imageId: DOCKER_IMAGE.id,
            digest: index.digest,
          },
        });
      });

      it('re-reads the manifest list', () => {
        expect(findRefetches()).toHaveBeenCalledWith({
          include: [getArtifactManifestsQuery],
        });
      });

      it('reports the delete as scheduled rather than done', () => {
        expect(mockToast.show).toHaveBeenCalledWith(
          'Manifest successfully scheduled for deletion.',
        );
      });

      it('releases the row once the request settles', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });

    describe('when the delete is refused', () => {
      beforeEach(async () => {
        executeDeleteMutation.mockResolvedValue(false);

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('claims nothing', () => {
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('leaves the list alone, because nothing was deleted', () => {
        expect(findRefetches()).not.toHaveBeenCalled();
      });

      it('releases the row rather than leaving it pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });

      it('accepts a new request for the same row', async () => {
        await openDeleteFor(0);
        await confirmDeletion();

        expect(executeDeleteMutation).toHaveBeenCalledTimes(2);
      });
    });

    describe('when the re-read fails after an accepted delete', () => {
      beforeEach(async () => {
        findRefetches().mockRejectedValue(new Error('network'));

        await openDeleteFor(0);
        await confirmDeletion();
      });

      it('surfaces the failure rather than swallowing it', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong. Please try again.',
          error: expect.any(Error),
          captureError: true,
        });
      });

      it('does not claim the delete as scheduled', () => {
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('releases the row rather than leaving it pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });

    describe('when it is confirmed twice while the first is in flight', () => {
      let release;

      beforeEach(async () => {
        executeDeleteMutation.mockReturnValue(
          new Promise((resolve) => {
            release = () => resolve(true);
          }),
        );

        await openDeleteFor(0);
        findDeleteModal().vm.$emit('confirm', index);
        findDeleteModal().vm.$emit('confirm', index);
        await nextTick();
      });

      it('sends one mutation', () => {
        expect(executeDeleteMutation).toHaveBeenCalledTimes(1);
      });

      it('marks only the row being deleted as pending', () => {
        expect(findMenuComponents().at(0).props('loading')).toBe(true);
        expect(findMenuComponents().at(1).props('loading')).toBe(false);
      });

      it('releases the row once the request settles', async () => {
        release();
        await waitForPromises();

        expect(findMenuComponents().at(0).props('loading')).toBe(false);
      });
    });
  });

  describe('the artifact delete verdict', () => {
    describe('when it allows', () => {
      beforeEach(() => createComponent({ permissions: mockRepositoryPermissions() }));

      it('offers the delete item on every row', () => {
        expect(findDeleteItems()).toHaveLength(mockManifests.length);
      });
    });

    describe('when it denies', () => {
      beforeEach(() => createComponent({ permissions: mockDeniedRepositoryPermissions() }));

      it('offers the delete item on no row', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });

      it('keeps every row menu and its pull command, which no verdict gates', () => {
        expect(findMenuComponents()).toHaveLength(mockManifests.length);
        expect(findPullCommandItems()).toHaveLength(mockManifests.length);
      });

      it('keeps the confirmation closed rather than unmounting it', () => {
        expect(findDeleteModal().props('target')).toBeNull();
      });
    });

    describe('when the read carrying it has not answered', () => {
      beforeEach(() => createComponent({ permissions: null }));

      it('offers the delete item on no row, so nothing is offered optimistically', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });
    });

    describe('when the artifact delete action alone denies', () => {
      beforeEach(() =>
        createComponent({ permissions: mockRepositoryPermissions({ deleteArtifact: false }) }),
      );

      it('offers the delete item on no row, because that action answers it', () => {
        expect(findDeleteItems()).toHaveLength(0);
      });
    });

    describe('when the artifact delete action alone allows', () => {
      beforeEach(() =>
        createComponent({ permissions: mockDeniedRepositoryPermissions({ deleteArtifact: true }) }),
      );

      it('offers the delete item on every row, because that action answers it', () => {
        expect(findDeleteItems()).toHaveLength(mockManifests.length);
      });
    });
  });
});
