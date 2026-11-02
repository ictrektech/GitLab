import { GlDrawer, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import ProfileListDrawer from 'ee/security_configuration/components/scan_profiles/profile_list_drawer.vue';

describe('ProfileListDrawer', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(ProfileListDrawer, {
      propsData: {
        open: true,
        title: 'Scan profiles',
        ...props,
      },
      slots: {
        default: '<div data-testid="default-slot">Default content</div>',
        list: '<div data-testid="list-slot">List content</div>',
        detail: '<div data-testid="detail-slot">Detail content</div>',
      },
      stubs: {
        GlDrawer: stubComponent(GlDrawer, {
          template: '<div><slot name="title" /><slot /></div>',
        }),
      },
    });
  };

  const findDrawer = () => wrapper.findComponent(GlDrawer);
  const findTitle = () => wrapper.find('h4');
  const findLoader = () => wrapper.findByTestId('profile-list-drawer-loader');
  const findList = () => wrapper.findByTestId('profile-list-drawer-list');
  const findDetail = () => wrapper.findByTestId('profile-list-drawer-detail');

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the title', () => {
      expect(findTitle().text()).toBe('Scan profiles');
    });

    it('links the drawer to its title', () => {
      expect(findDrawer().attributes('aria-labelledby')).toBe(findTitle().attributes('id'));
    });

    it('passes open to the drawer', () => {
      expect(findDrawer().props('open')).toBe(true);
    });

    it('sets the wide max width', () => {
      expect(findDrawer().classes()).toContain('!gl-max-w-5xl');
      expect(findDrawer().classes()).not.toContain('!gl-max-w-3xl');
    });

    it('renders the default, list and detail slots', () => {
      expect(wrapper.findByTestId('default-slot').exists()).toBe(true);
      expect(findList().find('[data-testid="list-slot"]').exists()).toBe(true);
      expect(findDetail().find('[data-testid="detail-slot"]').exists()).toBe(true);
    });

    it('hides the loader', () => {
      expect(findLoader().exists()).toBe(false);
    });
  });

  describe('with narrow true', () => {
    it('sets the smaller max width', () => {
      createComponent({ props: { narrow: true } });

      expect(findDrawer().classes()).toContain('!gl-max-w-3xl');
      expect(findDrawer().classes()).not.toContain('!gl-max-w-5xl');
    });
  });

  it('emits close on dismiss', () => {
    createComponent();

    findDrawer().vm.$emit('close');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  describe('while loading', () => {
    beforeEach(() => {
      createComponent({ props: { loading: true } });
    });

    it('shows the loader', () => {
      expect(findLoader().findComponent(GlSkeletonLoader).exists()).toBe(true);
    });

    it('hides the list and detail', () => {
      expect(findList().exists()).toBe(false);
      expect(findDetail().exists()).toBe(false);
    });
  });

  describe('with an error', () => {
    beforeEach(() => {
      createComponent({ props: { error: true } });
    });

    it('hides the list and detail', () => {
      expect(findList().exists()).toBe(false);
      expect(findDetail().exists()).toBe(false);
    });

    it('renders the default slot', () => {
      expect(wrapper.findByTestId('default-slot').exists()).toBe(true);
    });
  });

  describe('with showList false', () => {
    beforeEach(() => {
      createComponent({ props: { showList: false } });
    });

    it('hides the list', () => {
      expect(findList().exists()).toBe(false);
    });

    it('renders the detail', () => {
      expect(findDetail().exists()).toBe(true);
    });
  });
});
