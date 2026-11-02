import { BV_HIDE_TOOLTIP, BV_SHOW_TOOLTIP } from '~/lib/utils/constants';
import { hideGlTooltip, showGlTooltip } from '~/vue_shared/utils/tooltips';

describe('tooltips utils', () => {
  let vm;

  beforeEach(() => {
    vm = { $root: { $emit: jest.fn() } };
  });

  describe.each`
    helper           | eventName
    ${showGlTooltip} | ${BV_SHOW_TOOLTIP}
    ${hideGlTooltip} | ${BV_HIDE_TOOLTIP}
  `('$helper.name', ({ helper, eventName }) => {
    it(`emits ${eventName} with the id on the component's root`, () => {
      helper(vm, 'my-id');

      expect(vm.$root.$emit).toHaveBeenCalledTimes(1);
      expect(vm.$root.$emit).toHaveBeenCalledWith(eventName, 'my-id');
    });

    it(`emits ${eventName} without an id when none is given`, () => {
      helper(vm);

      expect(vm.$root.$emit.mock.calls).toEqual([[eventName]]);
    });
  });
});
