import { GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FeatureSettingsTableHeader from 'ee/ai/shared/feature_settings/feature_settings_table_header.vue';

describe('FeatureSettingsTableHeader', () => {
  let wrapper;

  const createComponent = ({ props = {}, slots = {} } = {}) => {
    wrapper = shallowMountExtended(FeatureSettingsTableHeader, {
      propsData: {
        title: 'GitLab Duo Chat',
        description: 'An AI assistant. %{linkStart}Learn more.%{linkEnd}',
        link: 'https://example.com/help',
        ...props,
      },
      stubs: { GlSprintf },
      slots,
    });
  };

  const findTitle = () => wrapper.find('h2');
  const findDescription = () => wrapper.find('p');
  const findLink = () => wrapper.findComponent(GlLink);
  const findActions = () => wrapper.findByTestId('table-header-actions');

  it('renders the title', () => {
    createComponent();

    expect(findTitle().text()).toBe('GitLab Duo Chat');
  });

  it('renders the description with a help link', () => {
    createComponent();

    expect(findDescription().text()).toContain('An AI assistant.');
    expect(findLink().attributes('href')).toBe('https://example.com/help');
  });

  describe('when no description is provided', () => {
    it('does not render the description paragraph', () => {
      createComponent({ props: { description: '' } });

      expect(findDescription().exists()).toBe(false);
    });
  });

  describe('actions slot', () => {
    it('does not render the actions container when the slot is empty', () => {
      createComponent();

      expect(findActions().exists()).toBe(false);
    });

    it('renders the actions container with slot content when provided', () => {
      createComponent({ slots: { actions: '<button data-testid="my-action">Act</button>' } });

      expect(findActions().exists()).toBe(true);
      expect(wrapper.findByTestId('my-action').exists()).toBe(true);
    });
  });
});
