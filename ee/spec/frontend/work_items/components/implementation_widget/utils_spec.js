import { AGENT_STEP_PILL_VARIANTS } from 'ee/work_items/components/implementation_widget/constants';
import {
  getVariantColor,
  isValidReadinessScore,
} from 'ee/work_items/components/implementation_widget/utils';

describe('workplan utils', () => {
  describe('getVariantColor', () => {
    it.each(Object.entries(AGENT_STEP_PILL_VARIANTS))(
      'returns the "%s" color for the "%s" variant',
      (variant, expectedColor) => {
        expect(getVariantColor(variant)).toBe(expectedColor);
      },
    );

    it('uses the neutral icon color for canceled workplans', () => {
      expect(getVariantColor('neutral')).toBe('var(--gl-status-neutral-icon-color)');
    });

    describe('when the variant is unknown', () => {
      it('falls back to the placeholder color', () => {
        expect(getVariantColor('unknown')).toBe(AGENT_STEP_PILL_VARIANTS.placeholder);
      });
    });
  });

  describe('isValidReadinessScore', () => {
    it.each([null, 0, 50, 100])('accepts %s', (score) => {
      expect(isValidReadinessScore(score)).toBe(true);
    });

    it.each([-1, 101, 50.5, undefined, NaN])('rejects %s', (score) => {
      expect(isValidReadinessScore(score)).toBe(false);
    });
  });
});
