import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import BulkUpdateControls from 'ee/ai/shared/feature_settings/bulk_update_controls.vue';
import ModelSelectDropdown from 'ee/ai/shared/feature_settings/model_select_dropdown.vue';

describe('BulkUpdateControls', () => {
  let wrapper;

  const items = [
    { value: 'model_a', text: 'Model A' },
    { value: 'model_b', text: 'Model B' },
  ];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(BulkUpdateControls, {
      propsData: {
        items,
        canReset: true,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const findDropdown = () => wrapper.findComponent(ModelSelectDropdown);
  const findResetButton = () => wrapper.findComponentByTestId('reset-to-default-button');
  const findTooltipWrapper = () => wrapper.findByTestId('bulk-update-tooltip');
  const findTooltip = () => getBinding(findTooltipWrapper().element, 'gl-tooltip');

  describe('bulk update dropdown', () => {
    it('passes the items through to the dropdown with a static "Bulk update" label', () => {
      createComponent();

      expect(findDropdown().props('items')).toBe(items);
      expect(findDropdown().props('placeholderDropdownText')).toBe('Bulk update');
      expect(findDropdown().props('selectedOption')).toBe(null);
    });

    it('emits select with the chosen model when the dropdown emits select', () => {
      createComponent();

      findDropdown().vm.$emit('select', 'model_a');

      expect(wrapper.emitted('select')).toEqual([['model_a']]);
    });

    describe('when models are available', () => {
      beforeEach(() => {
        createComponent();
      });

      it('enables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(false);
      });

      it('shows no tooltip', () => {
        expect(findTooltip().value).toBe('');
      });
    });

    describe('when no models are available', () => {
      beforeEach(() => {
        createComponent({ items: [] });
      });

      it('disables the dropdown', () => {
        expect(findDropdown().props('disabled')).toBe(true);
      });

      it('explains why in a tooltip', () => {
        expect(findTooltip().value).toBe('No models are available for this section');
      });
    });
  });

  describe('reset to default', () => {
    it('renders the reset button when canReset is true', () => {
      createComponent({ canReset: true });

      expect(findResetButton().exists()).toBe(true);
    });

    it('does not render the reset button when canReset is false', () => {
      createComponent({ canReset: false });

      expect(findResetButton().exists()).toBe(false);
    });

    it('emits reset when the reset button is clicked', () => {
      createComponent({ canReset: true });

      findResetButton().vm.$emit('click');

      expect(wrapper.emitted('reset')).toEqual([[]]);
    });
  });

  describe('when a bulk update is in flight (isSaving)', () => {
    beforeEach(() => {
      createComponent({ isSaving: true });
    });

    it('disables and shows loading on the dropdown', () => {
      expect(findDropdown().props('disabled')).toBe(true);
      expect(findDropdown().props('isLoading')).toBe(true);
    });

    it('disables the reset button', () => {
      expect(findResetButton().props('disabled')).toBe(true);
    });
  });
});
