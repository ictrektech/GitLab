import { GlIcon, GlTable } from '@gitlab/ui';
import upstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql.json';
import containerUpstreamFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.container.query.graphql.json';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import HelpPopover from '~/vue_shared/components/help_popover.vue';
import { UPSTREAM_REPOSITORIES_ORDER_HELP } from 'ee/packages_and_registries/artifact_registry/constants';
import UpstreamRepositoriesTable from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repositories_table.vue';
import UpstreamRepositoryActions from 'ee/packages_and_registries/artifact_registry/repositories/detail/upstream_repository_actions.vue';
import {
  mockDeniedRepositoryPermissions,
  mockFullUpstreamRepositories,
  mockUpstreamAssociation,
  mockUpstreamSettings,
} from '../../mock_data';

const upstreamRepositoriesFrom = (fixture) =>
  fixture.data.organization.artifactRegistryRepository.upstreamRepositories;

const serverUpstreamList = upstreamRepositoriesFrom(upstreamFixture);
const serverContainerUpstreamList = upstreamRepositoriesFrom(containerUpstreamFixture);

const withUpstreamPermissions = (upstreamRepositories, permissionsFor) =>
  upstreamRepositories.map((association) => ({
    ...association,
    upstreamRepository: {
      ...association.upstreamRepository,
      userPermissions: permissionsFor(association.upstreamRepository),
    },
  }));

const deniedUpstreamList = withUpstreamPermissions(serverUpstreamList, () =>
  mockDeniedRepositoryPermissions(),
);

const hostedDeleteArtifactOnlyList = withUpstreamPermissions(serverUpstreamList, ({ kind }) =>
  mockDeniedRepositoryPermissions({ deleteArtifact: kind === 'HOSTED' }),
);

const oneEditableUpstreamList = withUpstreamPermissions(serverUpstreamList, ({ name }) =>
  mockDeniedRepositoryPermissions({ updateRepository: name === 'payments-releases' }),
);

describe('ArtifactRegistryUpstreamRepositoriesTable', () => {
  let wrapper;

  const findTable = () => wrapper.findComponent(GlTable);
  const findHeaders = () => wrapper.findAll('thead th');
  const findRows = () => wrapper.findAll('tbody tr');
  const findHelpPopover = () => wrapper.findComponent(HelpPopover);
  const findPositions = () =>
    wrapper.findAllByTestId('upstream-position').wrappers.map((cell) => cell.text());
  const findNames = () =>
    wrapper.findAllByTestId('upstream-name').wrappers.map((cell) => cell.text());
  const findKinds = () =>
    wrapper.findAllByTestId('upstream-kind').wrappers.map((cell) => cell.text());
  const findActions = () => wrapper.findAllComponents(UpstreamRepositoryActions);
  const findRow = (index) => findRows().at(index);
  const findSource = (index) => findRow(index).find('[data-testid="upstream-source"]');
  const findUrl = (index) => findRow(index).find('[data-testid="upstream-url"]');
  const findHealth = (index) => findRow(index).find('[data-testid="upstream-health"]');
  const findSize = (index) => findRow(index).find('[data-testid="upstream-size"]');

  const createComponent = ({
    upstreamRepositories = serverUpstreamList,
    permissions = null,
  } = {}) => {
    wrapper = mountExtended(UpstreamRepositoriesTable, {
      propsData: {
        upstreamRepositories,
        repository: { name: 'maven-virtual', format: 'MAVEN' },
        permissions,
      },
      stubs: { UpstreamRepositoryActions: stubComponent(UpstreamRepositoryActions) },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  describe('the columns', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders Order, Repository, Type, Size, and Actions, and nothing else', () => {
      expect(findHeaders().wrappers.map((header) => header.text())).toEqual([
        expect.stringContaining('Order'),
        'Repository',
        'Type',
        'Size',
        'Actions',
      ]);
    });

    it('offers no sort control on any column, because the order carries meaning', () => {
      expect(wrapper.findAll('th[aria-sort]')).toHaveLength(0);
      expect(
        findTable()
          .props('fields')
          .every(({ sortable }) => !sortable),
      ).toBe(true);
    });
  });

  describe('the Actions column', () => {
    describe.each`
      description                                                      | upstreamRepositories            | permissions
      ${'every upstream and the page repository deny every action'}    | ${deniedUpstreamList}           | ${mockDeniedRepositoryPermissions()}
      ${'every upstream denies and the page verdicts have not loaded'} | ${deniedUpstreamList}           | ${null}
      ${'only hosted upstreams allow deleteArtifact'}                  | ${hostedDeleteArtifactOnlyList} | ${mockDeniedRepositoryPermissions()}
    `('when $description', ({ upstreamRepositories, permissions }) => {
      beforeEach(() => {
        createComponent({ upstreamRepositories, permissions });
      });

      it('drops the column', () => {
        expect(findHeaders().wrappers.map((header) => header.text())).toEqual([
          expect.stringContaining('Order'),
          'Repository',
          'Type',
          'Size',
        ]);
        expect(findActions()).toHaveLength(0);
      });
    });

    describe.each`
      description                                       | upstreamRepositories       | permissions
      ${'one upstream allows updateRepository'}         | ${oneEditableUpstreamList} | ${mockDeniedRepositoryPermissions()}
      ${'the page repository alone allows the removal'} | ${deniedUpstreamList}      | ${mockDeniedRepositoryPermissions({ deleteRepositoryUpstream: true })}
    `('when $description', ({ upstreamRepositories, permissions }) => {
      beforeEach(() => {
        createComponent({ upstreamRepositories, permissions });
      });

      it('keeps the column and a menu cell on every row', () => {
        expect(findHeaders().at(4).text()).toBe('Actions');
        expect(findActions()).toHaveLength(3);
      });
    });
  });

  describe('the row actions', () => {
    beforeEach(() => {
      createComponent();
    });

    it('mounts one actions menu per upstream', () => {
      expect(findActions()).toHaveLength(serverUpstreamList.length);
    });

    it('hands each menu the row upstream it acts on, not the association around it', () => {
      expect(findActions().wrappers.map((menu) => menu.props('upstreamRepository'))).toEqual(
        serverUpstreamList.map(({ upstreamRepository }) => upstreamRepository),
      );
    });

    it('hands each menu the association id of its row and the page repository', () => {
      expect(
        findActions().wrappers.map((menu) => [
          menu.props('associationId'),
          menu.props('repository'),
        ]),
      ).toEqual(
        serverUpstreamList.map(({ id }) => [id, { name: 'maven-virtual', format: 'MAVEN' }]),
      );
    });
  });

  describe.each([
    ['the package family', serverUpstreamList],
    ['the container family', serverContainerUpstreamList],
  ])('on %s', (_family, upstreamRepositories) => {
    beforeEach(() => {
      createComponent({ upstreamRepositories });
    });

    it('renders one row per upstream', () => {
      expect(findRows()).toHaveLength(upstreamRepositories.length);
    });

    it('renders the 1-based position in the Order cell, in the order received', () => {
      expect(findPositions()).toEqual(upstreamRepositories.map(({ position }) => String(position)));
    });

    it('renders the Order value as a badge, centred in a narrow column', () => {
      expect(
        wrapper
          .findAllByTestId('upstream-position')
          .wrappers.every((cell) => cell.element.classList.contains('gl-badge')),
      ).toBe(true);
      expect(findHeaders().at(0).classes()).toContain('gl-w-1/10');
      expect(findHeaders().at(0).find('span').classes()).toEqual(
        expect.arrayContaining(['gl-w-full', 'gl-justify-center']),
      );
      expect(findTable().props('fields')[0].tdClass).toContain('gl-text-center');
    });

    it('names the upstream repository, not the association', () => {
      expect(findNames()).toEqual(
        upstreamRepositories.map(({ upstreamRepository }) => upstreamRepository.name),
      );
    });

    it('renders the kind as a badge per row', () => {
      expect(findKinds()).toEqual(
        upstreamRepositories.map(({ upstreamRepository }) =>
          upstreamRepository.kind === 'REMOTE' ? 'Remote' : 'Hosted',
        ),
      );
      expect(
        wrapper
          .findAllByTestId('upstream-kind')
          .wrappers.every((cell) => cell.element.classList.contains('gl-badge')),
      ).toBe(true);
    });

    it('links no row anywhere, because navigating to an upstream is unspecified', () => {
      expect(findRows().wrappers.every((row) => row.findAll('a').length === 0)).toBe(true);
    });
  });

  describe('a mixed container-family list', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: serverContainerUpstreamList });
    });

    it('is handed no format to render, because the document selects none', () => {
      expect(
        serverContainerUpstreamList.map(({ upstreamRepository }) =>
          Object.keys(upstreamRepository).sort(),
        ),
      ).toEqual([
        ['__typename', 'id', 'kind', 'name', 'settings', 'sizeBytes', 'userPermissions'],
        ['__typename', 'id', 'kind', 'name', 'settings', 'sizeBytes', 'userPermissions'],
      ]);
    });
  });

  describe('a mixed container-family list whose summaries carry a format anyway', () => {
    beforeEach(() => {
      const formats = ['DOCKER', 'OCI'];

      createComponent({
        upstreamRepositories: serverContainerUpstreamList.map((association, index) => ({
          ...association,
          upstreamRepository: { ...association.upstreamRepository, format: formats[index] },
        })),
      });
    });

    it('renders every row', () => {
      expect(findNames()).toEqual(['docker-hub-proxy', 'base-images']);
    });

    it('renders neither format anywhere in its rows, so the rows read alike', () => {
      const body = wrapper.find('tbody').text();

      expect(body).not.toContain('Docker');
      expect(body).not.toContain('DOCKER');
      expect(body).not.toContain('OCI');
    });
  });

  describe('a list mixing a readable remote, a readable hosted, and an unreadable remote upstream', () => {
    beforeEach(() => {
      createComponent();
    });

    describe('the readable remote row', () => {
      it('renders the upstream URL as text, then the connection status', () => {
        expect(findUrl(0).text()).toBe('https://repo.maven.apache.org/maven2');
        expect(
          Array.from(findSource(0).element.children).map((child) => child.dataset.testid),
        ).toEqual(['upstream-url', 'upstream-health']);
      });

      it('offers no link and no copy action on the URL', () => {
        expect(findRow(0).findAll('a')).toHaveLength(0);
        expect(findRow(0).findComponent(ClipboardButton).exists()).toBe(false);
      });

      it('renders the connection status for this upstream', () => {
        expect(findHealth(0).attributes('aria-label')).toBe(
          'Connection status for maven-central-proxy: Healthy',
        );
      });

      it('renders the upstream size', () => {
        expect(findSize(0).text()).toBe('1.46 MiB');
      });
    });

    describe('the readable hosted row', () => {
      it('renders no URL and no connection status', () => {
        expect(findSource(1).exists()).toBe(false);
        expect(findHealth(1).exists()).toBe(false);
      });

      it('renders a zero size as a size, not as a blank', () => {
        expect(findSize(1).text()).toBe('0 B');
      });
    });

    describe('the remote row whose upstream the viewer cannot read', () => {
      it('keeps its name, its Remote badge, and its position', () => {
        expect(findNames()[2]).toBe('vendor-mirror');
        expect(findKinds()[2]).toBe('Remote');
        expect(findPositions()[2]).toBe('3');
      });

      it('renders no URL and no connection status, not even an unknown one', () => {
        expect(findSource(2).exists()).toBe(false);
        expect(findHealth(2).exists()).toBe(false);
        expect(findRow(2).findAllComponents(GlIcon)).toHaveLength(0);
      });

      it('leaves the Size cell blank', () => {
        expect(findSize(2).exists()).toBe(false);
        expect(findRow(2).findAll('td').at(3).text()).toBe('');
      });
    });

    it('holds no live region in any row', () => {
      expect(wrapper.findAll('tbody [role="status"]')).toHaveLength(0);
    });
  });

  describe('a hosted row whose upstream the viewer cannot read', () => {
    beforeEach(() => {
      createComponent({
        upstreamRepositories: [
          mockUpstreamAssociation({
            id: 'a1000000-0000-4000-8000-000000000001',
            upstreamId: 'd1000000-0000-4000-8000-000000000001',
            position: 1,
            name: 'payments-releases',
            format: 'MAVEN',
            kind: 'HOSTED',
            sizeBytes: null,
            settings: null,
          }),
        ],
      });
    });

    it('keeps its name, its Hosted badge, and its position', () => {
      expect(findNames()).toEqual(['payments-releases']);
      expect(findKinds()).toEqual(['Hosted']);
      expect(findPositions()).toEqual(['1']);
    });

    it('renders no URL and no connection status', () => {
      expect(findSource(0).exists()).toBe(false);
      expect(findHealth(0).exists()).toBe(false);
    });

    it('leaves the Size cell blank rather than rendering 0 B', () => {
      expect(findSize(0).exists()).toBe(false);
      expect(findRow(0).findAll('td').at(3).text()).toBe('');
    });
  });

  describe.each`
    lastHealthStatus | label          | variant      | icon                  | name
    ${'HEALTHY'}     | ${'Healthy'}   | ${'success'} | ${'status-success'}   | ${'Connection status for npmjs-proxy: Healthy'}
    ${'UNHEALTHY'}   | ${'Unhealthy'} | ${'danger'}  | ${'status-failed'}    | ${'Connection status for npmjs-proxy: Unhealthy'}
    ${'UNKNOWN'}     | ${'Unknown'}   | ${'subtle'}  | ${'severity-unknown'} | ${'Connection status for npmjs-proxy: Unknown'}
    ${null}          | ${'Unknown'}   | ${'subtle'}  | ${'severity-unknown'} | ${'Connection status for npmjs-proxy: Unknown'}
  `(
    'a remote row whose stored verdict is $lastHealthStatus',
    ({ lastHealthStatus, label, variant, icon, name }) => {
      beforeEach(() => {
        createComponent({
          upstreamRepositories: [
            mockUpstreamAssociation({
              id: 'a1000000-0000-4000-8000-000000000010',
              upstreamId: 'd1000000-0000-4000-8000-000000000010',
              position: 1,
              name: 'npmjs-proxy',
              format: 'NPM',
              kind: 'REMOTE',
              settings: mockUpstreamSettings({
                url: 'https://registry.npmjs.org',
                lastHealthStatus,
              }),
            }),
          ],
        });
      });

      it('draws the verdict as an icon with no text', () => {
        expect(findHealth(0).findComponent(GlIcon).props()).toMatchObject({ name: icon, variant });
        expect(findHealth(0).text()).toBe('');
      });

      it('shows the verdict in a tooltip', () => {
        expect(getBinding(findHealth(0).element, 'gl-tooltip')).toBeDefined();
        expect(findHealth(0).attributes('title')).toBe(label);
      });

      it('names the verdict and the upstream it describes, from a focusable control', () => {
        expect(wrapper.findByRole('button', { name }).exists()).toBe(true);
      });

      it('states no time, because the summary carries none', () => {
        expect(findRow(0).text()).not.toContain('Last verified');
      });
    },
  );

  describe.each`
    sizeBytes     | text
    ${'52428800'} | ${'50.00 MiB'}
    ${'0'}        | ${'0 B'}
    ${0}          | ${'0 B'}
    ${null}       | ${''}
  `('an upstream whose sizeBytes is $sizeBytes', ({ sizeBytes, text }) => {
    beforeEach(() => {
      createComponent({
        upstreamRepositories: [
          mockUpstreamAssociation({
            id: 'a1000000-0000-4000-8000-000000000011',
            upstreamId: 'd1000000-0000-4000-8000-000000000011',
            position: 1,
            name: 'base-images',
            format: 'OCI',
            kind: 'HOSTED',
            sizeBytes,
          }),
        ],
      });
    });

    it('renders the size in the Size cell', () => {
      expect(findRow(0).findAll('td').at(3).text()).toBe(text);
    });
  });

  describe('at the 20-upstream cap', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: mockFullUpstreamRepositories });
    });

    it('renders every row, because the resource is unpaginated', () => {
      expect(findRows()).toHaveLength(20);
    });

    it('renders the positions in ascending order', () => {
      expect(findPositions()).toEqual(Array.from({ length: 20 }, (_, index) => String(index + 1)));
    });
  });

  describe('the Order help affordance', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders in the Order header, not in a cell', () => {
      expect(findHeaders().at(0).findComponent(HelpPopover).exists()).toBe(true);
    });

    it('is not stranded by a stacked layout, which would hide the header that carries it', () => {
      const classes = wrapper.find('table').classes();

      expect(classes.some((name) => name.startsWith('b-table-stacked'))).toBe(false);
      expect(findHeaders()).toHaveLength(5);
    });

    it('states the resolution order and points at the Edit form', () => {
      expect(findHelpPopover().props('options')).toEqual({
        content: UPSTREAM_REPOSITORIES_ORDER_HELP,
      });
      expect(UPSTREAM_REPOSITORIES_ORDER_HELP).toBe(
        'Repositories are checked in this order when resolving an artifact. To reorder, edit this repository.',
      );
    });

    it('carries the information glyph the design names, not the help default', () => {
      expect(findHelpPopover().props('icon')).toBe('information-o');
    });
  });

  describe('when the list is empty', () => {
    beforeEach(() => {
      createComponent({ upstreamRepositories: [] });
    });

    it('says so, rather than leaving the headers standing over nothing', () => {
      expect(findNames()).toEqual([]);
      expect(wrapper.find('tbody').text()).toBe('There are no upstream repositories yet');
    });

    it('keeps the Order, Repository, Type and Size headers, so the empty list still reads as this table', () => {
      expect(findHeaders().wrappers.map((header) => header.text())).toEqual([
        expect.stringContaining('Order'),
        'Repository',
        'Type',
        'Size',
      ]);
    });
  });

  // A null or blank kind never reaches the badge: the server resolves those alongside a
  // top-level error, which the page renders instead of this table. An unmapped kind does.
  describe('a kind the label map does not carry', () => {
    beforeEach(() => {
      createComponent({
        upstreamRepositories: [
          mockUpstreamAssociation({
            id: 'a1000000-0000-4000-8000-000000000009',
            upstreamId: 'd1000000-0000-4000-8000-000000000009',
            position: 1,
            name: 'future-kind-source',
            format: 'MAVEN',
            kind: 'PROXY',
          }),
        ],
      });
    });

    it('renders the raw kind rather than an empty badge', () => {
      expect(findKinds()).toEqual(['PROXY']);
    });

    it('still renders the row, so an unmapped kind does not cost the list', () => {
      expect(findNames()).toEqual(['future-kind-source']);
    });
  });
});
