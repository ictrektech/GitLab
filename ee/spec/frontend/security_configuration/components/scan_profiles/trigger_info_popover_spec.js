import { GlButton, GlLink, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import TriggerInfoPopover from 'ee/security_configuration/components/scan_profiles/trigger_info_popover.vue';

describe('TriggerInfoPopover', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(TriggerInfoPopover, {
      propsData: {
        anchor: 'merge-request-pipeline',
        title: 'Merge Request Pipelines',
        description: 'GitLab scans each new commit.',
        helpLink: '/help/docs',
        ...props,
      },
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findLink = () => wrapper.findComponent(GlLink);

  it('renders an info button labelled with the trigger name', () => {
    createComponent();

    expect(findButton().attributes('aria-label')).toBe('About Merge Request Pipelines');
    expect(findButton().props('icon')).toBe('information-o');
  });

  it('targets the button from the popover', () => {
    createComponent();

    expect(findPopover().props('target')).toBe(findButton().attributes('id'));
  });

  it('renders the description and a Learn more link', () => {
    createComponent();

    expect(findPopover().text()).toContain('GitLab scans each new commit.');
    expect(findLink().attributes('href')).toBe('/help/docs');
    expect(findLink().text()).toBe('Learn more');
  });

  it('renders no Learn more link without a help link', () => {
    createComponent({ helpLink: '' });

    expect(findLink().exists()).toBe(false);
  });
});
