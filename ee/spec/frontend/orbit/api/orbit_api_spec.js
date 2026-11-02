import MockAdapter from 'axios-mock-adapter';
import {
  executeOrbitNamedQuery,
  executeOrbitQuery,
  fetchOrbitSchema,
  fetchOrbitTemplates,
} from 'ee/orbit/api/orbit_api';
import orbitQueryTemplatesQuery from 'ee/orbit/graphql/queries/orbit_query_templates.query.graphql';
import orbitSchemaQuery from 'ee/orbit/graphql/queries/orbit_schema.query.graphql';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';

describe('orbit_api', () => {
  let mock;

  const apolloReturning = (orbit) => ({
    query: jest.fn().mockResolvedValue({ data: { orbit } }),
  });

  beforeEach(() => {
    mock = new MockAdapter(axios);
    gon.api_version = 'v4';
  });

  afterEach(() => {
    mock.restore();
  });

  describe('executeOrbitQuery', () => {
    const queryUrl = '/api/v4/orbit/query';

    it('sends a POST with the query and default options', async () => {
      const queryPayload = { query_type: 'traversal', node: { id: 'u', entity: 'User' } };
      const responseData = { nodes: [], edges: [] };

      mock.onPost(queryUrl).reply(HTTP_STATUS_OK, responseData);

      const { data } = await executeOrbitQuery(queryPayload);

      expect(data).toEqual(responseData);
      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        query: queryPayload,
        response_format: 'raw',
      });
    });

    it('forwards custom responseFormat', async () => {
      const query = { query_type: 'traversal', node: { id: 'u', entity: 'User' } };

      mock.onPost(queryUrl).reply(HTTP_STATUS_OK, {});

      await executeOrbitQuery(query, { responseFormat: 'graph' });

      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        query,
        response_format: 'graph',
      });
    });

    it('rejects on server error', async () => {
      mock.onPost(queryUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

      await expect(executeOrbitQuery({})).rejects.toThrow();
    });
  });

  describe('executeOrbitNamedQuery', () => {
    const namedQueryUrl = '/api/v4/orbit/query/my_neighbors';

    it('sends a POST to the named query path with default options', async () => {
      const responseData = { result: { nodes: [], edges: [] } };

      mock.onPost(namedQueryUrl).reply(HTTP_STATUS_OK, responseData);

      const { data } = await executeOrbitNamedQuery('my_neighbors');

      expect(data).toEqual(responseData);
      expect(mock.history.post[0].url).toBe(namedQueryUrl);
      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        parameters: {},
        response_format: 'raw',
      });
    });

    it('forwards parameters, responseFormat and sourceType', async () => {
      mock.onPost('/api/v4/orbit/query/expand_neighbors').reply(HTTP_STATUS_OK, {});

      await executeOrbitNamedQuery('expand_neighbors', {
        parameters: { entity: 'Group', node_ids: [1], limit: 50 },
        responseFormat: 'llm',
        sourceType: 'code_intelligence',
      });

      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        parameters: { entity: 'Group', node_ids: [1], limit: 50 },
        response_format: 'llm',
        source_type: 'code_intelligence',
      });
    });

    it('escapes the query name in the URL', async () => {
      mock.onAny().reply(HTTP_STATUS_OK, {});

      await executeOrbitNamedQuery('a/b?c');

      expect(mock.history.post[0].url).toBe('/api/v4/orbit/query/a%2Fb%3Fc');
    });

    it('rejects on server error', async () => {
      mock.onPost(namedQueryUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

      await expect(executeOrbitNamedQuery('my_neighbors')).rejects.toThrow();
    });
  });

  describe('fetchOrbitTemplates', () => {
    const templates = [
      {
        name: 'my_neighbors',
        description: 'Immediate graph neighborhood of the current user.',
        query: 'MATCH (u:User) RETURN u.username',
      },
    ];

    it('returns the templates from the Orbit query', async () => {
      const apollo = apolloReturning({ queryTemplates: templates });

      await expect(fetchOrbitTemplates(apollo)).resolves.toEqual(templates);
      expect(apollo.query).toHaveBeenCalledWith({ query: orbitQueryTemplatesQuery });
    });

    it.each`
      case                              | orbit
      ${'the user cannot use Orbit'}    | ${{ queryTemplates: null }}
      ${'the user has no Orbit object'} | ${null}
    `('returns null when $case', async ({ orbit }) => {
      await expect(fetchOrbitTemplates(apolloReturning(orbit))).resolves.toBeNull();
    });

    describe('when the query fails', () => {
      const error = new Error('GraphQL error');

      it('rejects with the error', async () => {
        await expect(
          fetchOrbitTemplates({ query: jest.fn().mockRejectedValue(error) }),
        ).rejects.toBe(error);
      });
    });
  });

  describe('fetchOrbitSchema', () => {
    const graphqlSchema = {
      nodes: {
        nodes: [
          {
            name: 'MergeRequest',
            description: 'A merge request.',
            domain: { name: 'code_review' },
            primaryKey: 'id',
            labelProperty: 'title',
            properties: {
              nodes: [{ name: 'state', dataType: 'enum', nullable: false, enumValues: ['opened'] }],
            },
            display: { color: '#F59E0B', size: 28 },
          },
          {
            name: 'User',
            description: 'A user.',
            domain: { name: 'core' },
            primaryKey: 'id',
            labelProperty: 'username',
            properties: { nodes: [] },
            display: null,
          },
        ],
      },
      edges: {
        nodes: [
          {
            name: 'AUTHORED',
            description: 'Authorship.',
            endpoints: { nodes: [{ source: { name: 'User' }, target: { name: 'MergeRequest' } }] },
          },
        ],
      },
    };

    it('queries the schema and returns it in the shape the dashboard reads', async () => {
      const apollo = apolloReturning({ schema: graphqlSchema });

      await expect(fetchOrbitSchema(apollo)).resolves.toEqual({
        nodes: [
          {
            name: 'MergeRequest',
            domain: 'code_review',
            description: 'A merge request.',
            primary_key: 'id',
            label_field: 'title',
            properties: [
              { name: 'state', data_type: 'enum', nullable: false, enum_values: ['opened'] },
            ],
            style: { color: '#F59E0B', size: 28 },
          },
          {
            name: 'User',
            domain: 'core',
            description: 'A user.',
            primary_key: 'id',
            label_field: 'username',
            properties: [],
            style: null,
          },
        ],
        edges: [
          {
            name: 'AUTHORED',
            description: 'Authorship.',
            variants: [{ source_type: 'User', target_type: 'MergeRequest' }],
          },
        ],
      });
      expect(apollo.query).toHaveBeenCalledWith({ query: orbitSchemaQuery });
    });

    it('passes the fetch policy to Apollo', async () => {
      const apollo = apolloReturning({ schema: graphqlSchema });

      await fetchOrbitSchema(apollo, { fetchPolicy: 'network-only' });

      expect(apollo.query).toHaveBeenCalledWith({
        query: orbitSchemaQuery,
        fetchPolicy: 'network-only',
      });
    });

    it.each`
      case                                        | orbit
      ${'the user cannot use Orbit'}              | ${{ schema: null }}
      ${'the server does not have the field yet'} | ${{}}
      ${'the user has no Orbit object'}           | ${null}
    `('returns null when $case', async ({ orbit }) => {
      await expect(fetchOrbitSchema(apolloReturning(orbit))).resolves.toBeNull();
    });

    it('rejects when the query fails', async () => {
      const error = new Error('GraphQL error');

      await expect(fetchOrbitSchema({ query: jest.fn().mockRejectedValue(error) })).rejects.toBe(
        error,
      );
    });
  });
});
