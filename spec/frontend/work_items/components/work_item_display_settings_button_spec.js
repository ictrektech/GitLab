import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemDisplaySettingsButton from '~/work_items/components/work_item_display_settings_button.vue';

describe('WorkItemDisplaySettingsButton', () => {
  let wrapper;

  const findIconButton = () => wrapper.findComponentByTestId('display-settings-icon-button');

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(WorkItemDisplaySettingsButton, { propsData: props });
  };

  it('renders an icon-only button with a tooltip', () => {
    createComponent();

    expect(findIconButton().props('icon')).toBe('preferences');
    expect(findIconButton().text()).toBe('');
    expect(findIconButton().attributes('title')).toBe('Display');
    expect(findIconButton().attributes('aria-label')).toBe('Display');
  });

  it.each([true, false])('passes selected=%s to the button', (selected) => {
    createComponent({ props: { selected } });

    expect(findIconButton().props('selected')).toBe(selected);
  });

  it('emits click when the button is clicked', () => {
    createComponent();

    findIconButton().vm.$emit('click');

    expect(wrapper.emitted('click')).toHaveLength(1);
  });
});
