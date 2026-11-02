import { GlButton, GlTooltip } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ActionButton from 'ee/on_demand_scans/components/action_button.vue';
import { hideGlTooltip } from '~/vue_shared/utils/tooltips';

jest.mock('~/vue_shared/utils/tooltips');

describe('ActionButton', () => {
  let wrapper;

  // Props
  const actionType = 'action';
  const label = 'Action label';

  // Finders
  const findButton = () => wrapper.findComponent(GlButton);
  const findTooltip = () => wrapper.findComponent(GlTooltip);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ActionButton, {
      propsData: {
        actionType,
        label,
        ...props,
      },
    });
  };

  it('renders a button with a tooltip attached', () => {
    createComponent();
    const button = findButton();
    const tooltip = findTooltip();

    expect(button.exists()).toBe(true);
    expect(tooltip.exists()).toBe(true);
    expect(tooltip.attributes('target')).toBe(button.attributes('id'));
  });

  it('sets the label on the button and in the tooltip', () => {
    createComponent();

    expect(findButton().attributes('aria-label')).toBe(label);
    expect(findTooltip().text()).toBe(label);
  });

  it('hides the tooltip and emits click events on click', () => {
    createComponent();

    findButton().vm.$emit('click');

    expect(hideGlTooltip).toHaveBeenCalledWith(expect.anything(), findButton().attributes('id'));
    expect(wrapper.emitted('click')).toHaveLength(1);
  });

  it('does not set the loading state by default', () => {
    createComponent();

    expect(findButton().props('loading')).toBe(false);
  });

  it('passes the loading state down to the button', () => {
    createComponent({ isLoading: true });

    expect(findButton().props('loading')).toBe(true);
  });

  it('passes attributes down to the button', () => {
    const href = '/edit/path';
    createComponent({
      href,
    });

    expect(findButton().attributes('href')).toBe(href);
  });
});
