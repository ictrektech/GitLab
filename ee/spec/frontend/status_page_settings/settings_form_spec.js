import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SettingsBlock from '~/vue_shared/components/settings/settings_block.vue';
import StatusPageSettingsForm from 'ee/status_page_settings/components/settings_form.vue';
import { useStatusPageSettings } from 'ee/status_page_settings/store';

Vue.use(PiniaVuePlugin);

describe('Status Page settings form', () => {
  let wrapper;
  let pinia;
  let store;

  const createComponent = () => {
    wrapper = shallowMountExtended(StatusPageSettingsForm, {
      pinia,
      stubs: { SettingsBlock },
    });
  };

  const findForm = () => wrapper.findComponent({ ref: 'settingsForm' });
  const findToggleButton = () => wrapper.findByTestId('settings-block-toggle');
  const findSectionHeader = () => wrapper.findByTestId('settings-block-title');
  const findSectionSubHeader = () => wrapper.findComponent({ ref: 'sectionSubHeader' });

  beforeEach(() => {
    pinia = createTestingPinia();
    store = useStatusPageSettings();
    createComponent();
  });

  describe('default state', () => {
    it('should match the default snapshot', () => {
      // Transform snapshot for Vue2 compatibility
      expect(wrapper.html().replace(/ison=/g, 'is-on=')).toMatchSnapshot();
    });
  });

  it('renders header text', () => {
    expect(findSectionHeader().text()).toBe('Status page');
  });

  describe('expand/collapse button', () => {
    it('renders as an expand button by default', () => {
      expect(findToggleButton().attributes('aria-label')).toContain('Expand');
    });
  });

  describe('sub-header', () => {
    it('renders descriptive text', () => {
      expect(findSectionSubHeader().text()).toContain(
        'Configure file storage settings to link issues in this project to an external status page.',
      );
    });
  });

  describe('form', () => {
    it('writes input changes to the store', async () => {
      await wrapper.findComponent({ name: 'GlFormInput' }).vm.$emit('input', 'http://status.io');

      expect(store.url).toBe('http://status.io');
    });

    describe('submit button', () => {
      it('submits form on click', () => {
        findForm().trigger('submit');
        expect(store.updateStatusPageSettings).toHaveBeenCalledTimes(1);
      });
    });
  });
});
