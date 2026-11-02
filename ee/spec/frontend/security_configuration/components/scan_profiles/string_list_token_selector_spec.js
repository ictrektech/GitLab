import { GlTokenSelector } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StringListTokenSelector from 'ee/security_configuration/components/scan_profiles/string_list_token_selector.vue';

describe('StringListTokenSelector', () => {
  let wrapper;

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(StringListTokenSelector, {
      propsData: {
        ariaLabel: 'Paths to exclude',
        ...propsData,
      },
    });
  };

  const findTokenSelector = () => wrapper.findComponent(GlTokenSelector);

  const paste = (text) => {
    const event = new Event('paste', { bubbles: true, cancelable: true });
    event.clipboardData = { getData: () => text };
    wrapper.element.dispatchEvent(event);
    return event;
  };

  it('shows one token per entry of the value', () => {
    createComponent({ value: ['spec/', 'tmp/'] });

    expect(findTokenSelector().props('selectedTokens')).toEqual([
      { id: 0, name: 'spec/' },
      { id: 1, name: 'tmp/' },
    ]);
  });

  it('shows no tokens for a null value', () => {
    createComponent({ value: null });

    expect(findTokenSelector().props('selectedTokens')).toEqual([]);
  });

  it('emits an added token split on commas and newlines', () => {
    createComponent({ value: ['spec/'] });

    findTokenSelector().vm.$emit('input', [
      { id: 0, name: 'spec/' },
      { id: 'user-defined-token', name: 'semgrep, test' },
    ]);

    expect(wrapper.emitted('input')).toEqual([[['spec/', 'semgrep', 'test']]]);
  });

  it('emits the entries left after a removal', () => {
    createComponent({ value: ['spec/', 'tmp/'] });

    findTokenSelector().vm.$emit('input', [{ id: 1, name: 'tmp/' }]);

    expect(wrapper.emitted('input')).toEqual([[['tmp/']]]);
  });

  it('adds a pasted list as one token per entry', () => {
    createComponent({ value: ['spec/'] });

    const event = paste('semgrep, test\nspotbugs');

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.emitted('input')).toEqual([[['spec/', 'semgrep', 'test', 'spotbugs']]]);
  });

  it('keeps a single pasted entry as editable text', () => {
    createComponent({ value: ['spec/'] });

    const event = paste('semgrep');

    expect(event.defaultPrevented).toBe(false);
    expect(wrapper.emitted('input')).toBeUndefined();
  });

  it('keeps Enter from submitting the form', () => {
    createComponent();
    const event = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true });
    Object.defineProperty(event, 'target', { value: { value: 'spec/' } });

    findTokenSelector().vm.$emit('keydown', event);

    expect(event.defaultPrevented).toBe(true);
  });

  describe('typing a comma', () => {
    const typeThenPress = async (text, key) => {
      wrapper = mountExtended(StringListTokenSelector, {
        propsData: { ariaLabel: 'Paths to exclude', value: ['spec/'] },
      });
      const input = wrapper.find('input');
      await input.trigger('focus');
      await input.setValue(text);
      await nextTick();
      const event = new KeyboardEvent('keydown', { key, cancelable: true });
      input.element.dispatchEvent(event);
      return event;
    };

    it('adds the typed text as a token', async () => {
      const event = await typeThenPress('semgrep', ',');

      expect(event.defaultPrevented).toBe(true);
      expect(wrapper.emitted('input')).toEqual([[['spec/', 'semgrep']]]);
    });

    it('keeps an empty input from taking a comma', async () => {
      const event = await typeThenPress('', ',');

      expect(event.defaultPrevented).toBe(true);
      expect(wrapper.emitted('input')).toBeUndefined();
    });
  });

  describe('leaving the field', () => {
    const typeThenBlur = async (text) => {
      wrapper = mountExtended(StringListTokenSelector, {
        propsData: { ariaLabel: 'Paths to exclude', value: ['spec/'] },
      });
      const input = wrapper.find('input');
      await input.trigger('focus');
      await input.setValue(text);
      await nextTick();
      await input.trigger('blur');
    };

    it('adds the typed text as a token', async () => {
      await typeThenBlur('semgrep');

      expect(wrapper.emitted('input')).toEqual([[['spec/', 'semgrep']]]);
    });

    it('adds no token for an empty input', async () => {
      await typeThenBlur('');

      expect(wrapper.emitted('input')).toBeUndefined();
    });
  });

  it('hides the dropdown with its add prompt', () => {
    createComponent();

    expect(findTokenSelector().props('menuClass')).toBe('!gl-hidden');
  });

  it('sets view-only on the token selector', () => {
    createComponent({ disabled: true });

    expect(findTokenSelector().props('viewOnly')).toBe(true);
  });
});
