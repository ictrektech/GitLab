import { GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SeatAssignmentHint from 'ee/invite_members/components/seat_assignment_hint.vue';

describe('SeatAssignmentHint', () => {
  let wrapper;

  const findLink = () => wrapper.findComponent(GlLink);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SeatAssignmentHint, {
      propsData: {
        rootGroupPath: 'root-group',
        ...props,
      },
      stubs: { GlSprintf },
    });
  };

  it('renders the hint text', () => {
    createComponent();

    expect(wrapper.text()).toContain(
      'You can invite only users who already have a seat. Assign seats.',
    );
  });

  it('links to the seats page of the root group', () => {
    createComponent();

    expect(findLink().attributes('href')).toBe('/groups/root-group/-/usage_quotas#seats-quota-tab');
  });

  it('opens the seats page in a new tab to preserve the in-progress invite', () => {
    createComponent();

    expect(findLink().attributes('target')).toBe('_blank');
  });
});
