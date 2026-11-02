import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SeverityMeter from 'ee/vue_shared/components/severity_meter/severity_meter.vue';

describe('SeverityMeter', () => {
  let wrapper;

  const createComponent = ({ severity = 'HIGH', label = null, loading = false } = {}) => {
    wrapper = shallowMountExtended(SeverityMeter, {
      propsData: { severity, label, loading },
    });
  };

  const findMeter = () => wrapper.findByTestId('severity-meter');
  const findSegments = () => findMeter().findAll('span[aria-hidden="true"]');
  const segmentClasses = () => findSegments().wrappers.map((s) => s.classes());
  const filledFillClasses = () =>
    segmentClasses()
      .map((classes) => classes.find((c) => c.startsWith('severity-meter-fill-')))
      .filter(Boolean);

  it('always renders four segments', () => {
    createComponent();

    expect(findSegments()).toHaveLength(4);
  });

  describe('fill level', () => {
    it.each`
      severity      | filled | fillClass
      ${'LOW'}      | ${1}   | ${'severity-meter-fill-low'}
      ${'MEDIUM'}   | ${2}   | ${'severity-meter-fill-medium'}
      ${'HIGH'}     | ${3}   | ${'severity-meter-fill-high'}
      ${'CRITICAL'} | ${4}   | ${'severity-meter-fill-critical'}
    `('fills $filled segment(s) for $severity', ({ severity, filled, fillClass }) => {
      createComponent({ severity });

      // Uniform fill: every filled bar takes the current level's colour.
      expect(filledFillClasses()).toEqual(Array(filled).fill(fillClass));
    });

    it('leaves the remaining segments on the track colour', () => {
      createComponent({ severity: 'MEDIUM' });

      const trackSegments = segmentClasses().filter((classes) =>
        classes.includes('severity-meter-track'),
      );

      expect(trackSegments).toHaveLength(2);
    });
  });

  describe('when the severity is unknown', () => {
    it('fills no segments, leaving an empty grey meter', () => {
      createComponent({ severity: null });

      expect(filledFillClasses()).toHaveLength(0);
      expect(segmentClasses().every((classes) => classes.includes('severity-meter-track'))).toBe(
        true,
      );
    });
  });

  describe('when loading', () => {
    beforeEach(() => createComponent({ loading: true }));

    it('pulses every segment instead of showing a level', () => {
      expect(
        segmentClasses().every((classes) => classes.includes('gl-animate-skeleton-loader')),
      ).toBe(true);
      expect(filledFillClasses()).toHaveLength(0);
    });

    it('labels the meter as assessing', () => {
      expect(findMeter().attributes('aria-label')).toBe('Assessing severity');
    });
  });

  describe('accessible label', () => {
    it('names the severity by default', () => {
      createComponent({ severity: 'HIGH' });

      expect(findMeter().attributes('aria-label')).toBe('Severity: High');
    });

    it('falls back when the severity is unknown', () => {
      createComponent({ severity: null });

      expect(findMeter().attributes('aria-label')).toBe('Severity not available');
    });

    it('uses the label prop when provided, so callers can supply domain wording', () => {
      createComponent({ severity: 'HIGH', label: 'Risk level: High risk' });

      expect(findMeter().attributes('aria-label')).toBe('Risk level: High risk');
    });
  });

  it('exposes the meter as a single image to assistive tech, hiding the segments', () => {
    createComponent();

    expect(findMeter().attributes('role')).toBe('img');
    expect(findSegments().wrappers.every((s) => s.attributes('aria-hidden') === 'true')).toBe(true);
  });
});
