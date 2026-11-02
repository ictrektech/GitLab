import { GlButton, GlLink, GlPopover } from '@gitlab/ui';
import FlowUnavailableButton from 'ee/ai/shared/widgets/flow_unavailable_button.vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';

describe('FlowUnavailableButton component', () => {
  let wrapper;

  const defaultProps = {
    message: "Implementation with GitLab Duo isn't turned on for this project.",
    helpPath: '/help/user/work_items/workplan#implement-a-workplan-with-gitlab-duo',
  };

  const createComponent = ({ props = {}, slots = {}, attrs = {}, listeners = {} } = {}) => {
    wrapper = mountExtended(FlowUnavailableButton, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      slots,
      attrs,
      listeners,
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findPopoverLink = () => findPopover().findComponent(GlLink);

  beforeEach(() => {
    createComponent({ slots: { default: 'Implement' } });
  });

  it('renders the GlButton as the component root', () => {
    expect(wrapper.element).toBe(findButton().element);
    expect(wrapper.element.tagName).toBe('BUTTON');
  });

  it('renders the GlButton as accessible-disabled', () => {
    expect(findButton().props()).toMatchObject({ disabled: true, accessibleDisabled: true });
    expect(findButton().attributes('aria-disabled')).toBe('true');
    expect(findButton().attributes('disabled')).toBeUndefined();
  });

  it('does not set a title on the button', () => {
    expect(findButton().attributes('title')).toBeUndefined();
  });

  it('renders the default slot content inside the GlButton', () => {
    expect(findButton().text()).toContain('Implement');
  });

  it('sets the button data-testid', () => {
    expect(findButton().attributes('data-testid')).toBe('duo-workflow-action-button');
  });

  it('renders a popover targeting the button', () => {
    expect(findPopover().props()).toMatchObject({
      triggers: 'hover focus',
      placement: 'top',
    });
    expect(findPopover().props('target')()).toBe(findButton().element);
  });

  it('renders the message and a Learn more link in the popover', () => {
    expect(findPopover().text()).toContain(defaultProps.message);
    expect(findPopoverLink().text()).toBe('Learn more');
    expect(findPopoverLink().attributes()).toMatchObject({
      href: defaultProps.helpPath,
      target: '_blank',
    });
  });

  describe('when no help path is provided', () => {
    beforeEach(() => {
      createComponent({ props: { helpPath: '' }, slots: { default: 'Implement' } });
    });

    it('renders only the message in the popover', () => {
      expect(findPopover().text()).toBe(defaultProps.message);
      expect(findPopoverLink().exists()).toBe(false);
    });
  });

  describe('when a message slot is provided', () => {
    beforeEach(() => {
      createComponent({
        props: { helpPath: '' },
        slots: {
          default: 'Implement',
          message: '<span data-testid="custom-message">Custom <a href="/x">link</a> body</span>',
        },
      });
    });

    it('renders the slot in the popover instead of the message prop', () => {
      expect(findPopover().find('[data-testid="custom-message"]').text()).toBe('Custom link body');
      expect(findPopover().text()).not.toContain(defaultProps.message);
    });
  });

  describe('when clicked', () => {
    it('emits nothing and does not call a parent click listener', async () => {
      const onClick = jest.fn();
      createComponent({ slots: { default: 'Implement' }, listeners: { click: onClick } });

      await findButton().trigger('click');

      expect(onClick).not.toHaveBeenCalled();
      expect(wrapper.emitted()).toEqual({});
    });
  });

  describe('when the caller passes disabled as false', () => {
    beforeEach(() => {
      createComponent({ slots: { default: 'Implement' }, attrs: { disabled: false } });
    });

    it('keeps the GlButton disabled', () => {
      expect(findButton().props('disabled')).toBe(true);
      expect(findButton().attributes('aria-disabled')).toBe('true');
    });
  });

  describe('when size, variant and category props are provided', () => {
    beforeEach(() => {
      createComponent({
        props: { size: 'medium', variant: 'confirm', category: 'secondary' },
        slots: { default: 'Implement' },
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
