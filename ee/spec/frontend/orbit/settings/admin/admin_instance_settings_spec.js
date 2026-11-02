import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AdminInstanceSettings from 'ee/orbit/settings/admin/admin_instance_settings.vue';

describe('AdminInstanceSettings', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AdminInstanceSettings, {
      propsData: {
        autoIndexEnabled: false,
        duoDefaultEnabled: true,
        savingSetting: null,
        ...props,
      },
    });
  };

  const findAutoIndex = () => wrapper.findComponentByTestId('auto-index-toggle');
  const findDuoDefault = () => wrapper.findComponentByTestId('duo-default-toggle');

  describe('with no save running', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows each setting value', () => {
      expect(findAutoIndex().props('value')).toBe(false);
      expect(findDuoDefault().props('value')).toBe(true);
    });

    it.each`
      setting                              | findToggle        | value
      ${'orbit_auto_index_root_namespace'} | ${findAutoIndex}  | ${true}
      ${'orbit_dap_enabled_by_default'}    | ${findDuoDefault} | ${false}
    `('emits change for $setting', ({ setting, findToggle, value }) => {
      findToggle().vm.$emit('change', value);

      expect(wrapper.emitted('change')).toEqual([[{ setting, value }]]);
    });
  });

  describe('with a save error', () => {
    beforeEach(() => {
      createComponent({ saveError: 'Orbit settings are invalid' });
    });

    it('shows the error and emits dismiss-error on dismiss', () => {
      const alert = wrapper.findByTestId('orbit-settings-error');

      expect(alert.text()).toContain('Orbit settings are invalid');
      expect(wrapper.emitted('dismiss-error')).toBeUndefined();

      wrapper.findComponent(GlAlert).vm.$emit('dismiss');

      expect(wrapper.emitted('dismiss-error')).toEqual([[]]);
    });
  });

  describe('while the auto-index setting saves', () => {
    beforeEach(() => {
      createComponent({ savingSetting: 'orbit_auto_index_root_namespace' });
    });

    it('shows the spinner on that toggle and disables both', () => {
      expect(findAutoIndex().props()).toMatchObject({ isLoading: true, disabled: true });
      expect(findDuoDefault().props()).toMatchObject({ isLoading: false, disabled: true });
    });
  });
});
