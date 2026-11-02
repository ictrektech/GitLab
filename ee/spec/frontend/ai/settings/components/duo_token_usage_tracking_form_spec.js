import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox } from '@gitlab/ui';
import { nextTick } from 'vue';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import DuoTokenUsageTrackingForm from 'ee/ai/settings/components/duo_token_usage_tracking_form.vue';

describe('DuoTokenUsageTrackingForm', () => {
  let wrapper;

  const createComponent = ({ props = {}, injectedProps = {} } = {}) => {
    wrapper = extendedWrapper(
      shallowMount(DuoTokenUsageTrackingForm, {
        provide: {
          duoTokenUsageTrackingEnabled: true,
          ...injectedProps,
        },
        propsData: {
          ...props,
        },
        stubs: {
          GlFormCheckbox,
        },
      }),
    );
  };

  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);

  describe('when token usage tracking is on (default)', () => {
    beforeEach(() => {
      createComponent();
    });

    it('has the correct title', () => {
      expect(wrapper.find('h5').text()).toBe('Record GitLab Duo Non-Agentic Chat token usage');
    });

    it('has a label that says turning it off keeps existing records', () => {
      expect(findCheckbox().text()).toBe(
        'Record the input and output tokens that each GitLab Duo Non-Agentic Chat request uses, by user and model. Turning off this setting stops new records. Existing records are kept.',
      );
    });

    it('renders the checkbox checked', () => {
      expect(findCheckbox().props('checked')).toBe(true);
    });

    it('enables the checkbox', () => {
      expect(findCheckbox().props('disabled')).toBe(false);
    });

    describe('when the checkbox is cleared', () => {
      beforeEach(async () => {
        findCheckbox().vm.$emit('input', false);
        await nextTick();
        findCheckbox().vm.$emit('change', false);
      });

      it('emits change with false', () => {
        expect(wrapper.emitted('change')).toEqual([[false]]);
      });
    });
  });

  describe('when token usage tracking is off', () => {
    beforeEach(() => {
      createComponent({ injectedProps: { duoTokenUsageTrackingEnabled: false } });
    });

    it('renders the checkbox unchecked', () => {
      expect(findCheckbox().props('checked')).toBe(false);
    });
  });

  describe('when disabledCheckbox is true', () => {
    beforeEach(() => {
      createComponent({ props: { disabledCheckbox: true } });
    });

    it('disables the checkbox', () => {
      expect(findCheckbox().props('disabled')).toBe(true);
    });
  });
});
