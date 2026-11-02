import { GlButton } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';

import initCopyToClipboard, {
  CLIPBOARD_SUCCESS_EVENT,
  CLIPBOARD_ERROR_EVENT,
  I18N_ERROR_MESSAGE,
} from '~/behaviors/copy_to_clipboard';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';

describe('clipboard button', () => {
  let wrapper;

  const title = 'Copy this value';

  const createWrapper = (propsData = {}, options = {}) => {
    wrapper = mount(ClipboardButton, {
      propsData: {
        text: 'copy me',
        title,
        ...propsData,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      ...options,
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);

  const copy = (event = CLIPBOARD_SUCCESS_EVENT) => findButton().trigger(event);

  const endFeedback = async () => {
    jest.advanceTimersByTime(ClipboardButton.FEEDBACK_DURATION_MS);
    await nextTick();
  };

  describe('without gfm', () => {
    beforeEach(() => {
      createWrapper({ cssClass: 'btn-danger' });
    });

    it('renders a GlButton as the root element', () => {
      expect(findButton().exists()).toBe(true);
      expect(wrapper.element).toBe(findButton().element);
      expect(wrapper.attributes('data-clipboard-text')).toBe('copy me');
    });

    it('uses the title for the tooltip and the accessible name', () => {
      expect(findButton().attributes()).toMatchObject({
        title,
        'aria-label': title,
      });
    });

    it('shows the tooltip on hover and focus, but not on click', () => {
      const { modifiers } = getBinding(findButton().element, 'gl-tooltip');

      expect(modifiers).toEqual({ hover: true, focus: true, viewport: true, html: true });
    });

    it('lets the Vue component handle the copy feedback instead of the legacy handler', () => {
      expect(findButton().attributes('data-clipboard-handle-tooltip')).toBe('false');
    });

    it('should render provided classname', () => {
      expect(wrapper.classes()).toContain('btn-danger');
    });
  });

  describe('with gfm', () => {
    it('sets data-clipboard-text with gfm', () => {
      createWrapper({ gfm: '`path/to/file`' });

      expect(wrapper.attributes('data-clipboard-text')).toBe(
        '{"text":"copy me","gfm":"`path/to/file`"}',
      );
    });
  });

  it('renders default slot as button text', () => {
    createWrapper({}, { slots: { default: 'Foo bar' } });

    expect(findButton().text()).toBe('Foo bar');
  });

  it('re-emits button events', () => {
    const onClick = jest.fn();
    createWrapper({}, { listeners: { click: onClick } });

    findButton().trigger('click');

    expect(onClick).toHaveBeenCalled();
  });

  it('passes the category and variant props to the GlButton', () => {
    const category = 'tertiary';
    const variant = 'confirm';

    createWrapper({ title: '', text: '', category, variant });

    expect(findButton().props('category')).toBe(category);
    expect(findButton().props('variant')).toBe(variant);
  });

  describe('copy feedback', () => {
    it.each`
      event                      | icon       | message
      ${CLIPBOARD_SUCCESS_EVENT} | ${'check'} | ${'Copied to clipboard.'}
      ${CLIPBOARD_ERROR_EVENT}   | ${'error'} | ${I18N_ERROR_MESSAGE}
    `(
      'on $event, shows the $icon icon for 2 seconds and announces the result',
      async ({ event, icon, message }) => {
        createWrapper();
        expect(findButton().props('icon')).toBe('copy-to-clipboard');

        await copy(event);

        expect(findButton().props('icon')).toBe(icon);
        expect(findButton().element.ariaNotify).toHaveBeenCalledTimes(1);
        expect(findButton().element.ariaNotify).toHaveBeenCalledWith(message);

        await endFeedback();

        expect(findButton().props('icon')).toBe('copy-to-clipboard');
      },
    );

    it('does not change the tooltip title and the accessible name', async () => {
      createWrapper();

      await copy();

      expect(findButton().attributes()).toMatchObject({
        title,
        'aria-label': title,
      });
    });

    it('goes back to a custom icon afterwards', async () => {
      createWrapper({ icon: 'link' });

      await copy();
      expect(findButton().props('icon')).toBe('check');

      await endFeedback();

      expect(findButton().props('icon')).toBe('link');
    });

    it('restarts the 2 seconds when copying again', async () => {
      createWrapper();

      await copy();
      jest.advanceTimersByTime(1500);
      await copy();
      jest.advanceTimersByTime(1500);
      await nextTick();

      expect(findButton().props('icon')).toBe('check');

      jest.advanceTimersByTime(500);
      await nextTick();

      expect(findButton().props('icon')).toBe('copy-to-clipboard');
    });

    it('does not set aria-live on the button', () => {
      createWrapper();

      expect(findButton().attributes('aria-live')).toBeUndefined();
    });
  });

  describe('integration', () => {
    it('actually copies to clipboard', () => {
      initCopyToClipboard();

      document.execCommand = () => {};
      jest.spyOn(document, 'execCommand').mockImplementation(() => true);

      createWrapper({}, { attachTo: document.body });

      findButton().trigger('click');

      expect(document.execCommand).toHaveBeenCalledWith('copy');
    });
  });
});
