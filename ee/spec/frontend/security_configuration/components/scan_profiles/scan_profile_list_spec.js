import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScanProfileList from 'ee/security_configuration/components/scan_profiles/scan_profile_list.vue';
import InsufficientPermissionsPopover from 'ee/security_configuration/components/scan_profiles/insufficient_permissions_popover.vue';

describe('ScanProfileList', () => {
  let wrapper;

  const recommendedProfile = {
    id: 'gid://gitlab/Security::ScanProfile/1',
    name: 'Secret Detection (default)',
    description: 'The recommended profile',
    gitlabRecommended: true,
    projectCount: 5,
  };

  const customProfile = {
    id: 'gid://gitlab/Security::ScanProfile/2',
    name: 'A custom profile',
    description: 'One the group made',
    gitlabRecommended: false,
    projectCount: 2,
  };

  const createComponent = ({
    profiles = [recommendedProfile, customProfile],
    selectedId = '',
    rootGroupName = 'Acme Corp',
    canCreate = true,
  } = {}) => {
    wrapper = shallowMountExtended(ScanProfileList, {
      propsData: { profiles, selectedId, canCreate },
      provide: { rootGroupName },
    });
  };

  const findItems = () => wrapper.findAllByTestId('scan-profile-list-item');
  const findItemAt = (index) => findItems().at(index);
  const findProjectCounts = () => wrapper.findAllByTestId('scan-profile-list-item-project-count');
  const findProjectCountAt = (index) => findProjectCounts().at(index);
  const findNewProfileButton = () => wrapper.findComponentByTestId('scan-profile-new-button');
  const findPermissionsPopover = () => wrapper.findComponent(InsufficientPermissionsPopover);
  const findSearchInput = () => wrapper.findComponentByTestId('scan-profile-search');
  const findNoResults = () => wrapper.findByTestId('scan-profile-list-no-results');
  const setSearchTerm = async (term) => {
    findSearchInput().vm.$emit('input', term);
    await nextTick();
  };

  it('renders a row per profile', () => {
    createComponent();

    expect(findItems()).toHaveLength(2);
  });

  it('renders the name and description', () => {
    createComponent();

    expect(findItemAt(0).text()).toContain('Secret Detection (default)');
    expect(findItemAt(0).text()).toContain('The recommended profile');
  });

  it.each([
    ['GitLab', 0],
    ['Acme Corp', 1],
  ])('labels a profile as managed by %s', (label, index) => {
    createComponent();

    expect(findItemAt(index).text()).toContain(label);
  });

  it('marks the selected profile as current', () => {
    createComponent({ selectedId: customProfile.id });

    expect(findItemAt(0).attributes('aria-current')).toBeUndefined();
    expect(findItemAt(1).attributes('aria-current')).toBe('true');
  });

  it('emits select with the profile id when a row is clicked', () => {
    createComponent();

    findItemAt(1).trigger('click');

    expect(wrapper.emitted('select')).toEqual([[customProfile.id]]);
  });

  it('renders no rows and shows the empty state message for an empty list', () => {
    createComponent({ profiles: [] });

    expect(findItems()).toHaveLength(0);
    expect(wrapper.findByTestId('scan-profile-drawer-empty').text()).toBe(
      'There are no profiles for this scanner yet.',
    );
  });

  it('does not show the empty state message for a non-empty list', () => {
    createComponent();

    expect(wrapper.findByTestId('scan-profile-drawer-empty').exists()).toBe(false);
  });

  it.each([
    [0, 5],
    [1, 2],
  ])(
    'renders the project count with a screen-reader label for the profile at row %i',
    (index, count) => {
      createComponent();

      const projectCount = findProjectCountAt(index);

      expect(projectCount.find('[aria-hidden="true"]').text()).toBe(String(count));
      expect(projectCount.find('.gl-sr-only').text()).toBe(`${count} projects`);
    },
  );

  it('uses the singular form in the screen-reader label when the count is 1', () => {
    createComponent({
      profiles: [{ ...recommendedProfile, projectCount: 1 }],
    });

    expect(findProjectCountAt(0).find('.gl-sr-only').text()).toBe('1 project');
  });

  describe('search', () => {
    it('renders a search box with the profiles placeholder', () => {
      createComponent();

      expect(findSearchInput().exists()).toBe(true);
      expect(findSearchInput().attributes('placeholder')).toBe('Search profiles...');
    });

    it('shows every profile when the search box is empty', () => {
      createComponent();

      expect(findItems()).toHaveLength(2);
      expect(findNoResults().exists()).toBe(false);
    });

    it('filters the list by name, case-insensitively', async () => {
      createComponent();

      await setSearchTerm('CUSTOM');

      expect(findItems()).toHaveLength(1);
      expect(findItemAt(0).text()).toContain('A custom profile');
    });

    it('filters the list by description', async () => {
      createComponent();

      await setSearchTerm('recommended');

      expect(findItems()).toHaveLength(1);
      expect(findItemAt(0).text()).toContain('Secret Detection (default)');
    });

    it('shows a no-results message when no profile matches the query', async () => {
      createComponent();

      await setSearchTerm('nothing matches');

      expect(findItems()).toHaveLength(0);
      expect(findNoResults().exists()).toBe(true);
      expect(findNoResults().text()).toBe('No profiles match your search.');
    });

    it('ignores leading and trailing whitespace in the query', async () => {
      createComponent();

      await setSearchTerm('   Secret   ');

      expect(findItems()).toHaveLength(1);
      expect(findItemAt(0).text()).toContain('Secret Detection (default)');
    });

    it('does not show the no-results message when the list was empty to begin with', async () => {
      createComponent({ profiles: [] });

      await setSearchTerm('anything');

      expect(findNoResults().exists()).toBe(false);
      expect(wrapper.findByTestId('scan-profile-drawer-empty').exists()).toBe(true);
    });
  });

  describe('new profile button', () => {
    it('renders below the list with a plus icon and label', () => {
      createComponent();

      expect(findNewProfileButton().exists()).toBe(true);
      expect(findNewProfileButton().text()).toBe('Create new profile');
      expect(findNewProfileButton().props('icon')).toBe('plus');
    });

    it('emits create when clicked', () => {
      createComponent();

      findNewProfileButton().vm.$emit('click');

      expect(wrapper.emitted('create')).toHaveLength(1);
    });

    it('enables the button with create permission', () => {
      createComponent();

      expect(findNewProfileButton().props('disabled')).toBe(false);
      expect(findPermissionsPopover().exists()).toBe(false);
    });

    it('disables the button without create permission', () => {
      createComponent({ canCreate: false });

      expect(findNewProfileButton().props('disabled')).toBe(true);
      expect(findPermissionsPopover().props('target')()).toBe(
        wrapper.findByTestId('scan-profile-new-wrapper').element,
      );
      expect(findPermissionsPopover().props('description')).toBe(
        'To create scan profiles, you need the Security Manager, Maintainer, or Owner role in the top-level group.',
      );
    });
  });
});
