import { GlDisclosureDropdown, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import CreateButton from 'ee/packages_and_registries/artifact_registry/repositories/components/create_button.vue';
import RepositoriesHeader from 'ee/packages_and_registries/artifact_registry/repositories/list/repositories_header.vue';
import { mockDeniedNamespacePermissions, mockNamespacePermissions } from '../../mock_data';

describe('ArtifactRegistryRepositoriesHeader', () => {
  let wrapper;

  const findHeading = () => wrapper.findComponent(PageHeading);
  const findActions = () => wrapper.findByTestId('page-heading-actions');
  const findCreateButton = () => findActions().findComponent(CreateButton);
  const findDropdown = () => findCreateButton().findComponent(GlDisclosureDropdown);
  const findSummary = () => wrapper.findByTestId('statistics-summary');
  const findHeaderActions = () => wrapper.findComponentByTestId('header-actions');
  const findManageAccessItem = () => wrapper.findComponentByTestId('manage-access');

  // The heading is unstubbed so its actions slot renders, which is where the create
  // entry has to land rather than anywhere else in the header.
  const createComponent = ({ propsData = {}, stubs = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(RepositoriesHeader, {
      propsData: { permissions: mockNamespacePermissions(), ...propsData },
      provide,
      stubs: { PageHeading, ...stubs },
    });
  };

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the view in the page-level heading', () => {
      expect(findHeading().props('heading')).toBe('Repositories');
    });

    it('renders the create entry beside the heading', () => {
      expect(findCreateButton().exists()).toBe(true);
    });

    it('opens the create menu inward, because the entry sits at the right edge of the heading', () => {
      expect(findCreateButton().props('placement')).toBe('bottom-end');
    });
  });

  it('hands the namespace block to the create entry, which decides whether it renders', () => {
    const permissions = mockNamespacePermissions();

    createComponent({ propsData: { permissions } });

    expect(findCreateButton().props('permissions')).toEqual(permissions);
  });

  describe('when the create verdict allows', () => {
    beforeEach(() => {
      createComponent({ stubs: { CreateButton } });
    });

    it('renders the create dropdown', () => {
      expect(findDropdown().exists()).toBe(true);
    });
  });

  describe('when the create verdict denies', () => {
    beforeEach(() => {
      createComponent({
        propsData: { permissions: mockDeniedNamespacePermissions() },
        stubs: { CreateButton },
      });
    });

    it('renders the heading with no create dropdown', () => {
      expect(findHeading().props('heading')).toBe('Repositories');
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('before the block has resolved', () => {
    beforeEach(() => {
      createComponent({ propsData: { permissions: undefined }, stubs: { CreateButton } });
    });

    it('renders no create dropdown', () => {
      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('the Manage access menu item', () => {
    const organizationAccessPath = '/o/default/-/access/artifact-registry';

    describe('when the viewer can open the Organization access page', () => {
      beforeEach(() => {
        createComponent({ provide: { organizationAccessPath } });
      });

      it('renders the header menu in the heading actions', () => {
        expect(findActions().findComponentByTestId('header-actions').exists()).toBe(true);
        expect(findHeaderActions().props()).toMatchObject({
          icon: 'ellipsis_v',
          toggleText: 'More actions',
          textSrOnly: true,
          category: 'tertiary',
          noCaret: true,
          placement: 'bottom-end',
        });
      });

      it('links the item to the Organization access page', () => {
        expect(findManageAccessItem().props('item')).toEqual({
          text: 'Manage access',
          href: '/o/default/-/access/artifact-registry',
        });
      });
    });

    it.each`
      description                                              | permissions                                              | path
      ${'the viewer is not an Artifact Admin'}                 | ${mockNamespacePermissions({ createRepository: false })} | ${organizationAccessPath}
      ${'the namespace verdicts have not resolved'}            | ${undefined}                                             | ${organizationAccessPath}
      ${'the viewer cannot open the Organization access page'} | ${mockNamespacePermissions()}                            | ${null}
    `('renders no header menu when $description', ({ permissions, path }) => {
      createComponent({ propsData: { permissions }, provide: { organizationAccessPath: path } });

      expect(findHeaderActions().exists()).toBe(false);
      expect(findManageAccessItem().exists()).toBe(false);
    });
  });

  describe('the statistics summary', () => {
    const findRepositoriesCount = () => wrapper.findByTestId('repositories-count');
    const findStorageUsed = () => wrapper.findByTestId('storage-used');
    const iconOf = (item) => item.findComponent(GlIcon).props('name');
    // Collapsed as a browser collapses it: the label and the figure are sibling nodes.
    const textOf = (item) => item.text().replace(/\s+/g, ' ');

    // BigInt figures arrive as strings, and a count past a thousand is what tells a formatted
    // figure from the raw one.
    it('renders the repository count and the storage used as two iconed figures', () => {
      createComponent({
        propsData: { statistics: { repositoriesCount: '1234', deduplicatedSizeBytes: '2048' } },
      });

      expect(findSummary().classes()).toEqual(expect.arrayContaining(['gl-flex', 'gl-gap-5']));
      expect(findRepositoriesCount().text()).toBe('1,234 repositories');
      expect(iconOf(findRepositoriesCount())).toBe('infrastructure-registry');
      expect(textOf(findStorageUsed())).toBe('Storage used 2.00 KiB');
      expect(iconOf(findStorageUsed())).toBe('archive');
    });

    it('lays each figure out as icon then text, in the default text color', () => {
      createComponent({
        propsData: { statistics: { repositoriesCount: '1', deduplicatedSizeBytes: '2048' } },
      });

      expect(findRepositoriesCount().classes()).toEqual(
        expect.arrayContaining(['gl-flex', 'gl-items-center', 'gl-gap-2', 'gl-text-default']),
      );
    });

    it('names the storage figure for assistive technology, since the icon alone does not', () => {
      createComponent({
        propsData: { statistics: { repositoriesCount: '1', deduplicatedSizeBytes: '2048' } },
      });

      expect(findStorageUsed().find('.gl-sr-only').text()).toBe('Storage used');
    });

    it('renders the singular noun for a single repository', () => {
      createComponent({
        propsData: { statistics: { repositoriesCount: '1', deduplicatedSizeBytes: '2048' } },
      });

      expect(findRepositoriesCount().text()).toBe('1 repository');
    });

    it('renders a negative deduplicated size as zero rather than as negative bytes', () => {
      createComponent({
        propsData: { statistics: { repositoriesCount: '2', deduplicatedSizeBytes: '-2048' } },
      });

      expect(textOf(findStorageUsed())).toBe('Storage used 0 B');
    });

    it.each`
      statistics                                                    | present                  | absent
      ${{ repositoriesCount: null, deduplicatedSizeBytes: '2048' }} | ${findStorageUsed}       | ${findRepositoriesCount}
      ${{ repositoriesCount: '1234', deduplicatedSizeBytes: null }} | ${findRepositoriesCount} | ${findStorageUsed}
    `('renders only the known figure for $statistics', ({ statistics, present, absent }) => {
      createComponent({ propsData: { statistics } });

      expect(present().exists()).toBe(true);
      expect(absent().exists()).toBe(false);
    });

    it.each`
      description                | statistics
      ${'the field is null'}     | ${null}
      ${'both figures are null'} | ${{ repositoriesCount: null, deduplicatedSizeBytes: null }}
    `('omits the summary when $description', ({ statistics }) => {
      createComponent({ propsData: { statistics } });

      expect(findSummary().exists()).toBe(false);
    });
  });
});
