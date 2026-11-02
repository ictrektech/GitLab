import { GlLink, GlPopover } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import WorkplanAvailabilityPopover from 'ee/work_items/components/implementation_widget/workplan_availability_popover.vue';

describe('WorkplanAvailabilityPopover', () => {
  let wrapper;
  let target;
  const reason = "Workplan generation isn't turned on for this project.";

  const createComponent = () => {
    wrapper = mountExtended(WorkplanAvailabilityPopover, {
      propsData: { target: () => target, reason },
      stubs: { GlLink, GlPopover: true },
      attachTo: document.body,
    });
  };

  beforeEach(() => {
    target = document.createElement('button');
    document.body.appendChild(target);
  });

  afterEach(() => {
    target.remove();
  });

  beforeEach(() => {
    createComponent();
  });

  it('explains the restriction and links to the workplan documentation', () => {
    expect(wrapper.text()).toMatchInterpolatedText(`${reason} Learn more.`);
    expect(wrapper.findComponent(GlLink).attributes('href')).toBe(
      '/help/user/work_items/workplan#set-up-workplan-generation',
    );
  });

  it('keeps the popover next to its trigger in the document tab order', () => {
    expect(wrapper.findComponent(GlPopover).attributes('container')).toBe(wrapper.attributes('id'));
  });
});
