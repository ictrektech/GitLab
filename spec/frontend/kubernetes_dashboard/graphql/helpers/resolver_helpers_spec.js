import { CoreV1Api } from '@gitlab/cluster-client';
import {
  getK8sPods,
  handleClusterError,
  subscribeToSocket,
} from '~/kubernetes_dashboard/graphql/helpers/resolver_helpers';
import { getWatchManager } from '~/environments/services/websocket_connection_service';

jest.mock('~/environments/services/websocket_connection_service');

describe('handleClusterError', () => {
  describe('helper argument includes a response data', () => {
    describe("and the 'Content-Type' header of the response is an 'application/json'", () => {
      it('throws the error data', async () => {
        const errorData = {
          message: "Test error from the response with an 'application/json' Content-Type header",
        };
        const error = {
          response: {
            headers: {
              get: () => 'application/json',
            },
            json: jest.fn(() => Promise.resolve(errorData)),
          },
        };

        await expect(handleClusterError(error)).rejects.toMatchObject(errorData);
        expect(error.response.json).toHaveBeenCalled();
      });
    });

    describe("and the 'Content-Type' header of the response is not an 'application/json'", () => {
      it('throws a new error with a specific message', async () => {
        const error = {
          response: {
            headers: {
              get: () => 'text/html',
            },
          },
        };
        const expectedMessage =
          'There was a problem fetching cluster information. Refresh the page and try again.';

        await expect(handleClusterError(error)).rejects.toThrow(expectedMessage);
      });
    });
  });

  describe('helper argument does not include a response data', () => {
    it('throws the original error', async () => {
      const error = new Error('Test error message');

      await expect(handleClusterError(error)).rejects.toThrow('Test error message');
    });
  });
});

describe('getK8sPods', () => {
  it('passes each item, index, and source array to a custom mapper', async () => {
    const items = [{ metadata: { name: 'first' } }, { metadata: { name: 'second' } }];
    jest.spyOn(CoreV1Api.prototype, 'listCoreV1PodForAllNamespaces').mockResolvedValue({ items });
    const watcher = { on: jest.fn() };
    getWatchManager.mockReturnValue({ initConnection: jest.fn().mockResolvedValue(watcher) });
    const mapFn = jest.fn(
      (item, index, source) => `${item.metadata.name}:${index}/${source.length}`,
    );

    const result = await getK8sPods({
      client: { readQuery: jest.fn(), writeQuery: jest.fn() },
      configuration: {},
      mapFn,
    });

    expect(result).toEqual(['first:0/2', 'second:1/2']);
    expect(mapFn).toHaveBeenNthCalledWith(1, items[0], 0, items);
    expect(mapFn).toHaveBeenNthCalledWith(2, items[1], 1, items);
  });
});

describe('subscribeToSocket', () => {
  const config = { apiUrl: 'test-url' };
  const watchParams = { resource: 'pods', namespace: 'default' };
  const watchId = 'test-watch-id';
  let mockWatcher;
  let mockCacheParams;

  beforeEach(() => {
    mockWatcher = {
      on: jest.fn(),
      initConnection: jest.fn(),
    };

    mockCacheParams = {
      updateQueryCache: jest.fn(),
      updateConnectionStatusFn: jest.fn(),
    };

    getWatchManager.mockReturnValue(mockWatcher);
    mockWatcher.initConnection.mockResolvedValue(mockWatcher);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('initializes websocket connection with correct parameters', async () => {
    await subscribeToSocket({
      watchId,
      watchParams,
      cacheParams: mockCacheParams,
      config,
    });

    expect(getWatchManager).toHaveBeenCalledWith(config);
    expect(mockWatcher.initConnection).toHaveBeenCalledWith({
      message: { watchId, watchParams },
    });
  });

  it('handles connection initialization failure', async () => {
    mockWatcher.initConnection.mockRejectedValue(new Error('Connection failed'));

    await expect(
      subscribeToSocket({
        watchId,
        watchParams,
        cacheParams: mockCacheParams,
        config,
      }),
    ).rejects.toThrow('Failed to establish WebSocket connection');
  });
});
