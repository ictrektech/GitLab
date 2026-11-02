import { shallowMount } from '@vue/test-utils';
import WorkplanStatusBar from 'ee/work_items/components/implementation_widget/workplan_status_bar.vue';

describe('WorkplanStatusBar', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(WorkplanStatusBar, {
      propsData: { variant: 'neutral', ...props },
    });
  };

  it('stretches to fill its parent height', () => {
    createComponent();

    expect(wrapper.classes()).toEqual(expect.arrayContaining(['gl-h-full', 'gl-self-stretch']));
  });
});
