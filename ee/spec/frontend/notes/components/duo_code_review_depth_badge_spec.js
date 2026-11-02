import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoCodeReviewDepthBadge from 'ee/notes/components/duo_code_review_depth_badge.vue';

describe('DuoCodeReviewDepthBadge', () => {
  let wrapper;

  const createComponent = (depth) => {
    wrapper = shallowMountExtended(DuoCodeReviewDepthBadge, { propsData: { depth } });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);

  it.each`
    depth         | label
    ${'standard'} | ${'Standard review'}
    ${'deep'}     | ${'Deep review'}
  `('shows the $depth review depth', ({ depth, label }) => {
    createComponent(depth);

    expect(findBadge().text()).toBe(label);
  });

  it('does not render an unknown depth', () => {
    createComponent('quick');

    expect(findBadge().exists()).toBe(false);
  });
});
