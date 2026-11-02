import {
  buildGroupRows,
  filterGroupsBySearch,
  groupNote,
  statusFromServiceStatus,
} from 'ee/orbit/settings/admin/utils';
import { ACTION_TURN_OFF, ALL_GROUP_ACTIONS } from 'ee/orbit/shared/groups/constants';
import { ENABLED_AT, buildRow } from '../../shared/groups/mock_data';
import { buildGroup, buildOnGroup } from './mock_data';

describe('Orbit admin settings utils', () => {
  describe('buildGroupRows', () => {
    it('maps groups to rows with their exclusion, indexing state, areas, failure, and note', () => {
      const failure = { kind: 'rejected', message: 'Not allowed' };
      const areas = [{ __typename: 'OrbitIndexingArea', name: 'core', state: 'INDEXING' }];
      const acme = buildOnGroup('acme', 'INDEXING');
      acme.orbit.indexing.areas = areas;

      const rows = buildGroupRows({
        groups: [acme, buildGroup({ name: 'beta' })],
        excludedPaths: new Set(['beta']),
        failures: { beta: failure },
        allowedActions: ALL_GROUP_ACTIONS,
      });

      expect(rows).toEqual([
        buildRow({
          name: 'acme',
          isOn: true,
          indexingState: 'INDEXING',
          indexingAreas: areas,
          enabledAt: ENABLED_AT,
        }),
        buildRow({ name: 'beta', isExcluded: true, failure, note: 'Not allowed' }),
      ]);
    });

    it('gives every row the actions the instance allows', () => {
      const rows = buildGroupRows({
        groups: [buildGroup({ name: 'acme' })],
        excludedPaths: new Set(),
        failures: {},
        allowedActions: [ACTION_TURN_OFF],
      });

      expect(rows[0].allowedActions).toEqual([ACTION_TURN_OFF]);
    });
  });

  describe('groupNote', () => {
    it.each`
      description                       | row                                                                   | note
      ${'a failed action'}              | ${buildRow({ failure: { message: 'Not allowed' } })}                  | ${'Not allowed'}
      ${'a failed index'}               | ${buildRow({ isOn: true, indexingState: 'FAILED' })}                  | ${'GitLab Orbit could not index this group. Check the GitLab Orbit indexer logs.'}
      ${'an unknown state'}             | ${buildRow({ isOn: true, indexingState: 'UNKNOWN' })}                 | ${'GitLab Orbit has not reported a status for this group yet.'}
      ${'an excluded group that is on'} | ${buildRow({ isOn: true, indexingState: 'READY', isExcluded: true })} | ${'This group is excluded, so GitLab Orbit turns off for it within an hour.'}
      ${'an indexed group'}             | ${buildRow({ isOn: true, indexingState: 'READY' })}                   | ${null}
      ${'a group that is off'}          | ${buildRow({ isExcluded: true })}                                     | ${null}
    `('returns the note for $description', ({ row, note }) => {
      expect(groupNote(row)).toBe(note);
    });
  });

  describe('filterGroupsBySearch', () => {
    const groups = [
      buildGroup({ name: 'Acme', fullPath: 'acme-platform' }),
      buildGroup({ name: 'Beta', fullPath: 'beta' }),
    ];

    it.each`
      search        | expected
      ${'acm'}      | ${['Acme']}
      ${'PLATFORM'} | ${['Acme']}
      ${''}         | ${['Acme', 'Beta']}
    `('returns $expected for the search "$search"', ({ search, expected }) => {
      expect(filterGroupsBySearch(groups, search).map(({ name }) => name)).toEqual(expected);
    });
  });

  describe('statusFromServiceStatus', () => {
    it('maps the service status', () => {
      const components = [{ name: 'indexer', state: 'HEALTHY' }];

      expect(statusFromServiceStatus({ state: 'DEGRADED', version: '1.0', components })).toEqual({
        overall: 'DEGRADED',
        version: '1.0',
        components,
      });
    });

    describe('when there is no service status', () => {
      it('returns an unknown status', () => {
        expect(statusFromServiceStatus(null)).toEqual({
          overall: 'UNKNOWN',
          version: null,
          components: [],
        });
      });
    });
  });
});
