import { shallowMount } from '@vue/test-utils';
import { assertProps } from 'helpers/assert_props';
import ReadinessBar from 'ee/work_items/components/implementation_widget/readiness_bar.vue';
import { PLAN_READINESS_LEVELS } from 'ee/work_items/components/implementation_widget/constants';
import * as utils from 'ee/work_items/components/implementation_widget/utils';

describe('ReadinessBar', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(ReadinessBar, {
      propsData: {
        readinessLevel: PLAN_READINESS_LEVELS.HIGH,
        score: 85,
        ...props,
      },
    });
  };

  const findTrack = () => wrapper.find('span');
  const findFill = () => wrapper.find('span > span');

  describe('readinessLevel prop validator', () => {
    it.each(Object.values(PLAN_READINESS_LEVELS))('accepts the "$value" level', (level) => {
      expect(() => assertProps(ReadinessBar, { readinessLevel: level, score: 85 })).not.toThrow();
    });

    it('rejects an unknown level', () => {
      expect(() =>
        assertProps(ReadinessBar, { readinessLevel: { value: 'UNKNOWN' }, score: 85 }),
      ).toThrow();
    });
  });

  describe.each`
    score  | width
    ${0}   | ${'0%'}
    ${25}  | ${'25%'}
    ${72}  | ${'72%'}
    ${85}  | ${'85%'}
    ${100} | ${'100%'}
    ${-10} | ${'0%'}
    ${150} | ${'100%'}
  `('when score is $score', ({ score, width }) => {
    beforeEach(() => {
      createComponent({ score });
    });

    it(`fills the track to ${width}`, () => {
      expect(findFill().element.style.width).toBe(width);
    });
  });

  describe.each(Object.values(PLAN_READINESS_LEVELS))('when readiness level is $value', (level) => {
    beforeEach(() => {
      jest.spyOn(utils, 'getVariantColor').mockReturnValue('rgb(0, 0, 0)');
      createComponent({ readinessLevel: level, score: 50 });
    });

    it('colours the fill based on the level', () => {
      expect(utils.getVariantColor).toHaveBeenCalledWith(level.variant);
    });

    it('passes the style attribute to the fill element', () => {
      expect(findFill().attributes('style')).toContain('background-color: rgb(0, 0, 0);');
    });
  });

  describe('when an ariaLabel is provided', () => {
    beforeEach(() => {
      createComponent({ ariaLabel: 'Readiness: HIGH' });
    });

    it('renders it on the track element', () => {
      expect(findTrack().attributes('aria-label')).toBe('Readiness: HIGH');
    });
  });
});
