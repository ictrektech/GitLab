import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import AdminHealthCard from 'ee/orbit/settings/admin/admin_health_card.vue';
import ComponentHealthCard from 'ee/orbit/components/component_health_card.vue';

describe('AdminHealthCard', () => {
  let wrapper;

  const clickhouse = { name: 'clickhouse', state: 'HEALTHY' };

  const createComponent = ({ status, isLoading = false, loadError = null } = {}) => {
    wrapper = shallowMountExtended(AdminHealthCard, {
      propsData: {
        status: { overall: 'HEALTHY', version: '0.128.0', components: [clickhouse], ...status },
        isLoading,
        loadError,
      },
      stubs: { CrudComponent },
    });
  };

  const findCard = () => wrapper.findComponent(CrudComponent);
  const findTitle = () => wrapper.findByTestId('crud-title');
  const findIcon = () => findTitle().findComponent(GlIcon);
  const findServices = () => wrapper.findAllComponents(ComponentHealthCard);

  describe.each`
    overall        | title                                    | icon                | collapsed
    ${'HEALTHY'}   | ${'GitLab Orbit service is running'}     | ${'status-success'} | ${true}
    ${'MIGRATING'} | ${'GitLab Orbit service is running'}     | ${'status-success'} | ${true}
    ${'DEGRADED'}  | ${'GitLab Orbit service is degraded'}    | ${'status-alert'}   | ${false}
    ${'UNHEALTHY'} | ${'GitLab Orbit service is unavailable'} | ${'status-failed'}  | ${false}
    ${'UNKNOWN'}   | ${'GitLab Orbit service is unavailable'} | ${'status-failed'}  | ${false}
  `('when Orbit is $overall', ({ overall, title, icon, collapsed }) => {
    beforeEach(() => {
      createComponent({ status: { overall } });
    });

    it(`shows "${title}" and sets the services collapsed to ${collapsed}`, () => {
      expect(findTitle().text()).toBe(title);
      expect(findIcon().props('name')).toBe(icon);
      expect(findCard().props('collapsed')).toBe(collapsed);
    });
  });

  describe('when Orbit is healthy', () => {
    beforeEach(() => {
      createComponent();
    });

    it('lists the services and the version', () => {
      expect(findServices()).toHaveLength(1);
      expect(wrapper.text()).toContain('Version 0.128.0');
    });
  });

  describe('while the status loads', () => {
    beforeEach(() => {
      createComponent({ isLoading: true, status: { overall: 'UNKNOWN' } });
    });

    it('shows a neutral loading title and keeps the services collapsed', () => {
      expect(findTitle().text()).toBe('Checking the GitLab Orbit status…');
      expect(findTitle().findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(findIcon().exists()).toBe(false);
      expect(findCard().props()).toMatchObject({ isLoading: true, collapsed: true });
    });
  });

  describe('when Orbit reports no services', () => {
    beforeEach(() => {
      createComponent({ status: { overall: 'UNKNOWN', version: null, components: [] } });
    });

    it('shows the no services message and no version', () => {
      expect(wrapper.findByTestId('orbit-no-services').exists()).toBe(true);
      expect(wrapper.text()).not.toContain('Version');
    });
  });

  describe('when the status call fails', () => {
    beforeEach(() => {
      createComponent({
        status: { overall: 'UNKNOWN', version: null, components: [] },
        loadError: 'GitLab could not complete the request. Try again.',
      });
    });

    it('says the status could not be checked and shows the error', () => {
      expect(findTitle().text()).toBe('Could not check the GitLab Orbit status');
      expect(findCard().props('collapsed')).toBe(false);
      expect(wrapper.findByTestId('orbit-status-error').text()).toBe(
        'GitLab could not complete the request. Try again.',
      );
    });
  });
});
