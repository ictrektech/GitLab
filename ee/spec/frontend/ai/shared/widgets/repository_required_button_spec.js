import { GlButton, GlLink, GlPopover } from '@gitlab/ui';
import FlowUnavailableButton from 'ee/ai/shared/widgets/flow_unavailable_button.vue';
import RepositoryRequiredButton from 'ee/ai/shared/widgets/repository_required_button.vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';

describe('RepositoryRequiredButton component', () => {
  let wrapper;

  const defaultProps = {
    projectWebPath: '/gitlab-org/test-project',
  };

  const createComponent = ({ props = {}, slots = {}, attrs = {}, listeners = {} } = {}) => {
    wrapper = mountExtended(RepositoryRequiredButton, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      slots,
      attrs,
      listeners,
    });
  };

  const findFlowUnavailableButton = () => wrapper.findComponent(FlowUnavailableButton);
  const findButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findPopoverLink = () => findPopover().findComponent(GlLink);

  beforeEach(() => {
    createComponent({ slots: { default: 'My button' } });
  });

  it('renders a FlowUnavailableButton with the GlButton as the component root', () => {
    expect(findFlowUnavailableButton().exists()).toBe(true);
    expect(wrapper.element).toBe(findButton().element);
    expect(wrapper.element.tagName).toBe('BUTTON');
  });

  it('does not pass a help path, so there is no trailing Learn more link', () => {
    expect(findFlowUnavailableButton().props('helpPath')).toBe('');
    expect(findPopover().findAllComponents(GlLink)).toHaveLength(1);
  });

  it('renders a popover on hover and focus, above, targeting the button', () => {
    expect(findPopover().props()).toMatchObject({ triggers: 'hover focus', placement: 'top' });
    expect(findPopover().props('target')()).toBe(findButton().element);
    expect(findPopover().props('title')).toBeUndefined();
  });

  it('renders the full sentence in the popover', () => {
    expect(findPopover().text()).toBe(
      "This project doesn't have a repository yet. Add a repository to get started with flows.",
    );
  });

  it('links to the project from the popover', () => {
    expect(findPopoverLink().text()).toBe('Add a repository');
    expect(findPopoverLink().attributes('href')).toBe(defaultProps.projectWebPath);
  });

  it('renders the GlButton as accessible-disabled', () => {
    expect(findButton().props()).toMatchObject({ disabled: true, accessibleDisabled: true });
    expect(findButton().attributes('aria-disabled')).toBe('true');
    expect(findButton().attributes('disabled')).toBeUndefined();
  });

  it('renders the default slot content inside the GlButton', () => {
    expect(findButton().text()).toContain('My button');
  });

  it('sets the button data-testid', () => {
    expect(findButton().attributes('data-testid')).toBe('duo-workflow-action-button');
  });

  describe('when no default slot is given', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders only the icon and the popover in the button', () => {
      expect(findButton().props('icon')).toBe('tanuki-ai');
      expect(findButton().text()).toBe(findPopover().text());
    });
  });

  describe('when clicked', () => {
    it('emits nothing and does not call a parent click listener', async () => {
      const onClick = jest.fn();
      createComponent({ slots: { default: 'My button' }, listeners: { click: onClick } });

      await findButton().trigger('click');

      expect(onClick).not.toHaveBeenCalled();
      expect(wrapper.emitted()).toEqual({});
    });
  });

  describe('when attributes are passed by the caller', () => {
    beforeEach(() => {
      createComponent({
        slots: { default: 'My button' },
        attrs: {
          'aria-label': 'Fix pipeline',
          'data-foo': 'bar',
          class: 'gl-self-start',
        },
      });
    });

    it('lands them on the button element', () => {
      expect(findButton().attributes()).toMatchObject({
        'aria-label': 'Fix pipeline',
        'data-foo': 'bar',
      });
      expect(findButton().classes()).toContain('gl-self-start');
    });
  });

  describe('when the caller passes disabled as false', () => {
    beforeEach(() => {
      createComponent({ slots: { default: 'My button' }, attrs: { disabled: false } });
    });

    it('keeps the GlButton disabled', () => {
      expect(findButton().props('disabled')).toBe(true);
      expect(findButton().attributes('aria-disabled')).toBe('true');
    });
  });

  describe('size, variant and category defaults', () => {
    it('defaults size to small, variant to default and category to primary', () => {
      expect(findButton().props()).toMatchObject({
        size: 'small',
        variant: 'default',
        category: 'primary',
      });
    });
  });

  describe('when size, variant and category props are provided', () => {
    beforeEach(() => {
      createComponent({
        props: { size: 'medium', variant: 'confirm', category: 'secondary' },
        slots: { default: 'My button' },
      });
    });

    it('forwards them to the GlButton', () => {
      expect(findButton().props()).toMatchObject({
        size: 'medium',
        variant: 'confirm',
        category: 'secondary',
      });
    });
  });
});
