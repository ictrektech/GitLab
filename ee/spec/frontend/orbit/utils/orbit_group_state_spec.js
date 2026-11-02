import { useFakeDate } from 'helpers/fake_date';
import {
  groupsIndexingVersion,
  isIndexingQueued,
  isInitialIndexing,
  isOrbitReady,
  pendingProjectCount,
  sumItemCounts,
} from 'ee/orbit/utils/orbit_group_state';
import { buildGroupWithPendingProjects, buildItemCountGroup, buildOrbitGroup } from '../mock_data';

describe('orbit_group_state', () => {
  describe('isOrbitReady', () => {
    describe('when the indexing state is READY', () => {
      it('is ready', () => {
        expect(isOrbitReady({ orbit: { indexing: { state: 'READY' } } })).toBe(true);
      });
    });

    describe('when the indexing state is anything else', () => {
      it('is not ready', () => {
        expect(isOrbitReady({ orbit: { indexing: { state: 'INDEXING' } } })).toBe(false);
      });
    });

    describe('when there is no status yet', () => {
      it('is not ready', () => {
        expect(isOrbitReady({ orbit: { indexing: null } })).toBe(false);
      });
    });
  });

  describe('isIndexingQueued', () => {
    useFakeDate(2026, 9, 15, 12, 0, 0);

    describe('when Orbit has no status and the recently-enabled window has passed', () => {
      it('is queued', () => {
        expect(isIndexingQueued({ orbit: { enabledAt: '2026-10-15T11:40:00Z' } })).toBe(true);
      });
    });

    describe('when Orbit has no status but is still inside the window', () => {
      it('is not queued', () => {
        expect(isIndexingQueued({ orbit: { enabledAt: '2026-10-15T11:55:00Z' } })).toBe(false);
      });
    });

    describe('when the user has no Orbit access', () => {
      it('is queued', () => {
        expect(isIndexingQueued({ orbit: null })).toBe(true);
      });
    });

    describe('when Orbit already reports a status', () => {
      it('is not queued', () => {
        expect(
          isIndexingQueued({
            orbit: { enabledAt: '2026-10-15T11:40:00Z', indexing: { state: 'INDEXING' } },
          }),
        ).toBe(false);
      });
    });
  });

  describe('isInitialIndexing', () => {
    useFakeDate(2026, 9, 15, 12, 0, 0);

    const notStarted = (enabledAt) => buildOrbitGroup({ state: 'NOT_STARTED', enabledAt });
    const sdlcIndexing = buildOrbitGroup({
      state: 'INDEXING',
      areas: [
        { name: 'core', state: 'READY' },
        { name: 'ci', state: 'INDEXING' },
        { name: 'source_code', state: 'INDEXING' },
      ],
    });

    it.each`
      scenario                                  | group                                     | expected
      ${'indexing is ready'}                    | ${buildOrbitGroup({ state: 'READY' })}    | ${false}
      ${'indexing failed'}                      | ${buildOrbitGroup({ state: 'FAILED' })}   | ${false}
      ${'indexing runs without area states'}    | ${buildOrbitGroup({ state: 'INDEXING' })} | ${true}
      ${'an SDLC area is indexing'}             | ${sdlcIndexing}                           | ${true}
      ${'only source code is indexing'}         | ${buildGroupWithPendingProjects()}        | ${false}
      ${'indexing not started within 3 days'}   | ${notStarted('2026-10-13T12:00:00Z')}     | ${true}
      ${'indexing not started after 3 days'}    | ${notStarted('2026-04-22T14:04:36Z')}     | ${false}
      ${'indexing not started, no enable time'} | ${notStarted(null)}                       | ${false}
      ${'the state is unknown'}                 | ${buildOrbitGroup({ state: 'UNKNOWN' })}  | ${false}
      ${'there is no status'}                   | ${{ orbit: null }}                        | ${false}
      ${'the status failed to load'}            | ${{ orbit: { indexing: null } }}          | ${false}
    `('is $expected when $scenario', ({ group, expected }) => {
      expect(isInitialIndexing(group)).toBe(expected);
    });
  });

  describe('pendingProjectCount', () => {
    const withProjects = (state, projects) =>
      buildOrbitGroup({ state, areas: [{ name: 'core', state: 'READY' }], projects });

    it.each`
      scenario                                      | group                                                                   | expected
      ${'only source code is indexing'}             | ${buildGroupWithPendingProjects({ pending: 2 })}                        | ${2}
      ${'projects that used all attempts'}          | ${withProjects('INDEXING', { indexed: 97, totalKnown: 100, gaps: 1 })}  | ${2}
      ${'the group is ready'}                       | ${withProjects('READY', { indexed: 100, totalKnown: 100, gaps: 0 })}    | ${0}
      ${'the first backfill is running'}            | ${buildOrbitGroup({ state: 'INDEXING' })}                               | ${0}
      ${'the counts are missing'}                   | ${withProjects('INDEXING', null)}                                       | ${0}
      ${'the counts are null'}                      | ${withProjects('INDEXING', { indexed: null, totalKnown: null })}        | ${0}
      ${'more projects are indexed than are known'} | ${withProjects('INDEXING', { indexed: 101, totalKnown: 100, gaps: 0 })} | ${0}
    `('is $expected when $scenario', ({ group, expected }) => {
      expect(pendingProjectCount(group)).toBe(expected);
    });
  });

  describe('groupsIndexingVersion', () => {
    it('joins the path, the state, and the area states of each group', () => {
      const group = buildOrbitGroup({
        state: 'INDEXING',
        areas: [
          { name: 'core', state: 'READY' },
          { name: 'ci', state: 'INDEXING' },
        ],
      });

      expect(groupsIndexingVersion([group, { fullPath: 'off', orbit: { indexing: null } }])).toBe(
        `${group.fullPath}:INDEXING:core=READY:ci=INDEXING|off:`,
      );
    });
  });

  describe('sumItemCounts', () => {
    it('sums the counts of each area and item type across the groups', () => {
      const groups = [
        buildItemCountGroup({
          id: 1,
          domains: { ci: { Pipeline: 1200, Job: 3 }, core: { User: 2 } },
        }),
        buildItemCountGroup({ id: 2, domains: { ci: { Pipeline: 5 } } }),
        { orbit: { itemCounts: null } },
      ];

      expect(sumItemCounts(groups)).toEqual({
        domains: { ci: 1208, core: 2 },
        entities: { pipeline: 1205, job: 3, user: 2 },
      });
    });
  });
});
