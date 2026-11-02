import { RESOURCE_ACCESS_ERROR } from '~/graphql_shared/constants';
import {
  actionItemsFor,
  completeBulkProgress,
  confirmKindFor,
  groupsForAction,
  hasActiveIndexing,
  hasIndexingError,
  indexStatusLabel,
  indexStatusWarningFor,
  indexingAreasFor,
  isIndexingNow,
  mapWithConcurrency,
  reportFirstRequestError,
  reportRequestError,
  requestErrorFor,
  startBulkProgress,
  summarizeBulkAction,
  turnOnTrackingLabel,
} from 'ee/orbit/shared/groups/utils';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { buildRow } from './mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('Orbit groups utils', () => {
  describe('groupsForAction', () => {
    const on = buildRow({ name: 'on', isOn: true });
    const off = buildRow({ name: 'off' });
    const excluded = buildRow({ name: 'excluded', isExcluded: true });

    it.each`
      action       | expected
      ${'turnOn'}  | ${[off]}
      ${'turnOff'} | ${[on]}
      ${'exclude'} | ${[on, off]}
      ${'include'} | ${[excluded]}
    `('returns the rows that $action changes', ({ action, expected }) => {
      expect(groupsForAction([on, off, excluded], action)).toEqual(expected);
    });
  });

  describe('actionItemsFor', () => {
    it('lists only the actions that change a selected row', () => {
      expect(actionItemsFor([buildRow({ isOn: true, isExcluded: true })])).toEqual([
        { value: 'turnOff', text: 'Turn off GitLab Orbit' },
        { value: 'include', text: 'Remove exclusion' },
      ]);
    });

    it('lists no action for an empty selection', () => {
      expect(actionItemsFor([])).toEqual([]);
    });
  });

  describe('indexStatusLabel', () => {
    it.each`
      row                                                    | label
      ${buildRow()}                                          | ${'Not indexed'}
      ${buildRow({ turnOnAction: 'trial_ended' })}           | ${'Indexing paused'}
      ${buildRow({ turnOnAction: 'credits_used_up' })}       | ${'Indexing paused'}
      ${buildRow({ isOn: true })}                            | ${'Status not available'}
      ${buildRow({ isOn: true, indexingState: 'READY' })}    | ${'Indexed'}
      ${buildRow({ isOn: true, indexingState: 'INDEXING' })} | ${'Indexing'}
      ${buildRow({ isOn: true, indexingState: 'NEW' })}      | ${'Status not available'}
    `(
      'returns "$label" for state $row.indexingState and action $row.turnOnAction',
      ({ row, label }) => {
        expect(indexStatusLabel(row)).toBe(label);
      },
    );
  });

  describe('confirmKindFor', () => {
    const on = buildRow({ name: 'on', isOn: true });
    const off = buildRow({ name: 'off' });

    it.each`
      action       | groups       | expected
      ${'turnOff'} | ${[on]}      | ${'turnOff'}
      ${'exclude'} | ${[off, on]} | ${'exclude'}
      ${'exclude'} | ${[off]}     | ${null}
      ${'turnOn'}  | ${[off]}     | ${null}
      ${'include'} | ${[on]}      | ${null}
    `('returns $expected for $action', ({ action, groups, expected }) => {
      expect(confirmKindFor(action, groups)).toBe(expected);
    });
  });

  describe('hasIndexingError', () => {
    it.each`
      row                                                   | expected
      ${buildRow({ isOn: true, indexingState: 'FAILED' })}  | ${true}
      ${buildRow({ isOn: true, indexingState: 'READY' })}   | ${false}
      ${buildRow({ isOn: false, indexingState: 'FAILED' })} | ${false}
    `('returns $expected for on=$row.isOn and state $row.indexingState', ({ row, expected }) => {
      expect(hasIndexingError(row)).toBe(expected);
    });
  });

  describe('isIndexingNow', () => {
    it.each`
      row                                                       | expected
      ${buildRow({ isOn: true, indexingState: 'INDEXING' })}    | ${true}
      ${buildRow({ isOn: true, indexingState: 'NOT_STARTED' })} | ${false}
      ${buildRow({ isOn: false, indexingState: 'INDEXING' })}   | ${false}
    `('returns $expected for on=$row.isOn and state $row.indexingState', ({ row, expected }) => {
      expect(isIndexingNow(row)).toBe(expected);
    });
  });

  describe('indexingAreasFor', () => {
    const indexingAreas = [
      { name: 'security', state: 'FAILED' },
      { name: 'core', state: 'READY' },
      { name: 'ci', state: 'INDEXING' },
      { name: 'plan', state: null },
      { name: 'new_area', state: 'READY' },
    ];

    it('returns the known areas in the Overview order, with a label and an icon', () => {
      expect(
        indexingAreasFor(buildRow({ isOn: true, indexingState: 'FAILED', indexingAreas })),
      ).toEqual([
        {
          key: 'core',
          label: 'Core',
          stateLabel: 'Indexed',
          isIndexing: false,
          icon: 'status-success',
          iconVariant: 'success',
        },
        {
          key: 'plan',
          label: 'Planning',
          stateLabel: 'Status not available',
          isIndexing: false,
          icon: 'status-neutral',
          iconVariant: 'subtle',
        },
        {
          key: 'ci',
          label: 'CI/CD',
          stateLabel: 'Indexing',
          isIndexing: true,
          icon: 'status-neutral',
          iconVariant: 'subtle',
        },
        {
          key: 'security',
          label: 'Security',
          stateLabel: 'Indexing failed',
          isIndexing: false,
          icon: 'status-failed',
          iconVariant: 'danger',
        },
      ]);
    });

    it.each`
      description                | row
      ${'an indexed group'}      | ${buildRow({ isOn: true, indexingState: 'READY', indexingAreas })}
      ${'a group that is off'}   | ${buildRow({ isOn: false, indexingState: 'INDEXING', indexingAreas })}
      ${'a group with no areas'} | ${buildRow({ isOn: true, indexingState: 'INDEXING' })}
    `('returns no areas for $description', ({ row }) => {
      expect(indexingAreasFor(row)).toEqual([]);
    });
  });

  describe('hasActiveIndexing', () => {
    it.each`
      state            | expected
      ${'NOT_STARTED'} | ${true}
      ${'INDEXING'}    | ${true}
      ${'READY'}       | ${false}
      ${'FAILED'}      | ${false}
    `('returns $expected for a row in state $state', ({ state, expected }) => {
      expect(hasActiveIndexing([buildRow({ isOn: true, indexingState: state })])).toBe(expected);
    });
  });

  describe('indexStatusWarningFor', () => {
    it('returns the server message', () => {
      expect(indexStatusWarningFor([], 'Knowledge graph request failed')).toBe(
        'Knowledge graph request failed',
      );
    });

    describe('with no server message', () => {
      it.each`
        description                                     | rows                                                                             | expected
        ${'a row that is on and has no status'}         | ${[buildRow({ isOn: true, indexingState: null })]}                               | ${'GitLab Orbit did not return the index status of some groups.'}
        ${'rows that are on with a status, or are off'} | ${[buildRow({ isOn: true, indexingState: 'READY' }), buildRow({ isOn: false })]} | ${null}
      `('returns $expected for $description', ({ rows, expected }) => {
        expect(indexStatusWarningFor(rows, null)).toBe(expected);
      });
    });
  });

  describe('turnOnTrackingLabel', () => {
    it.each`
      description                     | trials                  | label
      ${'every group starts a trial'} | ${[true, true]}         | ${'start_trial'}
      ${'no group starts a trial'}    | ${[false, false]}       | ${'turn_on'}
      ${'some groups start a trial'}  | ${[true, false, false]} | ${'mixed'}
    `('returns $label when $description', ({ trials, label }) => {
      const groups = trials.map((startsTrial) => ({ startsTrial }));

      expect(turnOnTrackingLabel(groups)).toBe(label);
    });
  });

  describe('mapWithConcurrency', () => {
    it('runs at most the limit of tasks at a time and keeps the order of the results', async () => {
      let running = 0;
      let mostRunning = 0;
      const task = async (item) => {
        running += 1;
        mostRunning = Math.max(mostRunning, running);
        await Promise.resolve();
        running -= 1;
        return item * 2;
      };

      expect(await mapWithConcurrency([1, 2, 3, 4, 5, 6, 7], 3, task)).toEqual([
        2, 4, 6, 8, 10, 12, 14,
      ]);
      expect(mostRunning).toBe(3);
    });
  });

  describe('bulk progress', () => {
    const groups = [buildRow({ name: 'acme' }), buildRow({ name: 'beta' })];

    it('starts with every group pending', () => {
      expect(startBulkProgress('turnOn', groups)).toEqual({
        action: 'turnOn',
        done: 0,
        total: 2,
        pendingPaths: ['acme', 'beta'],
      });
    });

    it('counts a done group and removes it from the pending paths', () => {
      expect(completeBulkProgress(startBulkProgress('turnOn', groups), 'acme')).toMatchObject({
        done: 1,
        pendingPaths: ['beta'],
      });
    });
  });

  describe('summarizeBulkAction', () => {
    it('collects the failures by path and lists them in the result', () => {
      const failure = { kind: 'rejected', message: 'Not allowed' };
      const results = [
        { group: buildRow({ name: 'acme' }), failure: null },
        { group: buildRow({ name: 'beta' }), failure },
      ];

      expect(summarizeBulkAction('turnOn', results)).toEqual({
        failures: { beta: failure },
        failedPaths: ['beta'],
        result: {
          action: 'turnOn',
          total: 2,
          failed: [{ name: 'beta', fullPath: 'beta', message: 'Not allowed' }],
        },
      });
    });
  });

  describe('reportRequestError', () => {
    it('reports a server error to Sentry', () => {
      const error = { networkError: { statusCode: 500 } };

      expect(reportRequestError(error).kind).toBe('server');
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    it('does not report a rejected request', () => {
      expect(reportRequestError({ graphQLErrors: [{ message: 'Nope' }] }).kind).toBe('rejected');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('shows the given message for no access', () => {
      const error = { networkError: { statusCode: 403 } };

      expect(reportRequestError(error, { noAccessMessage: 'Sign in' })).toEqual({
        kind: 'noAccess',
        message: 'Sign in',
      });
    });
  });

  describe('reportFirstRequestError', () => {
    describe('when requests fail with server and network errors', () => {
      const serverError = new Error('Server error');

      beforeEach(() => {
        reportFirstRequestError([
          { failure: null },
          { failure: { kind: 'rejected', message: 'Not allowed' } },
          { failure: { kind: 'server' }, error: serverError },
          { failure: { kind: 'network' }, error: new Error('Network error') },
        ]);
      });

      it('reports only the first of these errors to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
        expect(Sentry.captureException).toHaveBeenCalledWith(serverError);
      });
    });

    describe('when no request fails', () => {
      beforeEach(() => {
        reportFirstRequestError([{ failure: null }, { failure: { kind: 'noAccess' } }]);
      });

      it('reports nothing to Sentry', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });
  });

  describe('requestErrorFor', () => {
    const noAccess = {
      kind: 'noAccess',
      message: 'You do not have permission to do this. Check that Admin Mode is on.',
    };
    const network = {
      kind: 'network',
      message: 'The request did not reach GitLab. Check your connection and try again.',
    };
    const server = { kind: 'server', message: 'GitLab could not complete the request. Try again.' };

    it.each`
      description                            | error                                                                          | expected
      ${'a GraphQL 403'}                     | ${{ networkError: { statusCode: 403 } }}                                       | ${noAccess}
      ${'an axios 401'}                      | ${{ response: { status: 401, data: { message: 'Admin mode is inactive.' } } }} | ${noAccess}
      ${'the GraphQL access error'}          | ${{ graphQLErrors: [{ message: RESOURCE_ACCESS_ERROR }] }}                     | ${noAccess}
      ${'an axios 404'}                      | ${{ response: { status: 404, data: {} } }}                                     | ${noAccess}
      ${'a GraphQL error'}                   | ${{ graphQLErrors: [{ message: 'Group not found' }] }}                         | ${{ kind: 'rejected', message: 'Group not found' }}
      ${'an axios 422 with a message'}       | ${{ response: { status: 422, data: { message: 'Bad value' } } }}               | ${{ kind: 'rejected', message: 'Bad value' }}
      ${'a GraphQL network error'}           | ${{ networkError: new Error('Failed to fetch') }}                              | ${network}
      ${'an axios request with no response'} | ${{ request: {} }}                                                             | ${network}
      ${'a GraphQL 500'}                     | ${{ networkError: { statusCode: 500 } }}                                       | ${server}
      ${'an axios 500 with a message'}       | ${{ response: { status: 500, data: { message: 'Boom' } } }}                    | ${server}
    `('maps $description', ({ error, expected }) => {
      expect(requestErrorFor(error)).toEqual(expected);
    });
  });
});
