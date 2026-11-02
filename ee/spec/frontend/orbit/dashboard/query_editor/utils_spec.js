import { queryErrorFor, queryResultRows } from 'ee/orbit/dashboard/query_editor/utils';

describe('Orbit query editor utils', () => {
  describe('queryResultRows', () => {
    describe('when the result has aggregation rows', () => {
      it('returns the flattened rows', () => {
        const result = {
          rows: [{ severity: 'high', count: 12 }],
          nodes: [{ type: 'User', id: 1 }],
        };

        expect(queryResultRows(result)).toEqual([{ severity: 'high', count: 12 }]);
      });
    });

    describe('when the result has only nodes', () => {
      it('returns one row for each node with its type', () => {
        const result = { nodes: [{ type: 'User', id: 1, username: 'root' }] };

        expect(queryResultRows(result)).toEqual([{ type: 'User', id: 1, username: 'root' }]);
      });

      it('puts the type and id first, then the properties by name', () => {
        const result = { nodes: [{ type: 'User', id: 1, username: 'root', name: 'Root' }] };

        expect(Object.keys(queryResultRows(result)[0])).toEqual(['type', 'id', 'name', 'username']);
      });
    });
  });

  describe('queryErrorFor', () => {
    describe('when the API rejects the query', () => {
      it('returns the message of the API', () => {
        const error = { response: { status: 400, data: { message: 'Unknown relationship type' } } };

        expect(queryErrorFor(error)).toEqual({
          kind: 'invalid_query',
          message: 'Unknown relationship type',
        });
      });
    });

    describe('when the user has no Orbit default group', () => {
      it('returns a billing group error with the link to the preferences', () => {
        const error = {
          response: {
            status: 422,
            data: {
              code: 'billing_namespace_required',
              message: 'Select a default group in your preferences to run GitLab Orbit queries.',
              deep_link: 'http://gitlab.example.com/-/profile/preferences',
              candidates: [{ id: 1, name: 'acme' }],
            },
          },
        };

        expect(queryErrorFor(error)).toEqual({
          kind: 'billing_group_required',
          message: 'Select a default group in your preferences to run GitLab Orbit queries.',
          preferencesUrl: 'http://gitlab.example.com/-/profile/preferences',
        });
      });
    });

    describe('when the API rejects the query with no message', () => {
      it('returns a generic invalid query message', () => {
        expect(queryErrorFor({ response: { status: 422, data: {} } })).toEqual({
          kind: 'invalid_query',
          message: 'Invalid query. Check query parameters and try again.',
        });
      });
    });

    describe('when the user has no Orbit access', () => {
      it('returns a no access error', () => {
        const error = {
          response: {
            status: 403,
            data: { message: '403 Forbidden - No Orbit enabled namespaces available' },
          },
        };

        expect(queryErrorFor(error)).toEqual({
          kind: 'no_access',
          message: '403 Forbidden - No Orbit enabled namespaces available',
        });
      });
    });

    describe.each([401, 402, 404, 429])('when the API refuses the request with %s', (status) => {
      it('returns a rejected request error with the message of the API', () => {
        const error = { response: { status, data: { message: 'Request refused' } } };

        expect(queryErrorFor(error)).toEqual({
          kind: 'request_rejected',
          message: 'Request refused',
        });
      });
    });

    describe('when the rate limit refuses the request', () => {
      it('returns the text inside the message object', () => {
        const error = {
          response: {
            status: 429,
            data: {
              message: {
                error: 'This endpoint has been requested too many times. Try again later.',
              },
            },
          },
        };

        expect(queryErrorFor(error)).toEqual({
          kind: 'request_rejected',
          message: 'This endpoint has been requested too many times. Try again later.',
        });
      });
    });

    describe('when the API refuses the request with no message', () => {
      it('returns a generic failure message', () => {
        expect(queryErrorFor({ response: { status: 429, data: {} } })).toEqual({
          kind: 'request_rejected',
          message: 'Could not run the query. Try again.',
        });
      });
    });

    describe('when the API fails', () => {
      it('returns a server error that hides the API message', () => {
        const error = { response: { status: 500, data: { message: 'panic at row 0x1234' } } };

        expect(queryErrorFor(error)).toEqual({
          kind: 'server',
          message: 'Could not run the query. Try again.',
        });
      });
    });

    describe('when the request has no response', () => {
      it('returns a server error', () => {
        expect(queryErrorFor(new Error('Network Error'))).toEqual({
          kind: 'server',
          message: 'Could not run the query. Try again.',
        });
      });
    });
  });
});
