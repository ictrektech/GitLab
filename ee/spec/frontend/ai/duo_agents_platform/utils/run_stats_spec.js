import { useFakeDate } from 'helpers/fake_date';
import { fillDailyVolume, successRate } from 'ee/ai/duo_agents_platform/utils/run_stats';

describe('run stats utils', () => {
  describe('successRate', () => {
    it.each`
      finishedRuns | failedRuns | expected
      ${3}         | ${1}       | ${75}
      ${199}       | ${1}       | ${99}
      ${0}         | ${5}       | ${0}
      ${0}         | ${0}       | ${null}
    `(
      'returns $expected for $finishedRuns finished and $failedRuns failed runs',
      ({ finishedRuns, failedRuns, expected }) => {
        expect(successRate({ finishedRuns, failedRuns })).toBe(expected);
      },
    );
  });

  describe('fillDailyVolume', () => {
    useFakeDate('2026-10-13T01:00:00Z');

    it('returns a point for each of the 31 UTC dates and fills missing dates with 0', () => {
      const points = fillDailyVolume([
        { date: '2026-09-13', runs: 2 },
        { date: '2026-10-13', runs: 5 },
      ]);

      expect(points).toHaveLength(31);
      expect(points[0]).toEqual(['Sep 13', 2]);
      expect(points[30]).toEqual(['Oct 13', 5]);
      expect(points.slice(1, 30).every(([, runs]) => runs === 0)).toBe(true);
    });
  });
});
