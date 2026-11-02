// API bindings for the Orbit query engine and schema.
import { buildApiUrl } from '~/api/api_utils';
import axios from '~/lib/utils/axios_utils';
import orbitQueryTemplatesQuery from '../graphql/queries/orbit_query_templates.query.graphql';
import orbitSchemaQuery from '../graphql/queries/orbit_schema.query.graphql';

const ORBIT_QUERY_PATH = '/api/:version/orbit/query';
const ORBIT_NAMED_QUERY_PATH = '/api/:version/orbit/query/:name';

/** POST a structured query to the Orbit query engine. */
export const executeOrbitQuery = (query, { responseFormat = 'raw', sourceType } = {}) => {
  const body = { query, response_format: responseFormat };
  if (sourceType) body.source_type = sourceType;
  return axios.post(buildApiUrl(ORBIT_QUERY_PATH), body);
};

/** POST a server-defined named query to the Orbit query engine. */
export const executeOrbitNamedQuery = (
  name,
  { parameters = {}, responseFormat = 'raw', sourceType } = {},
) => {
  const url = buildApiUrl(ORBIT_NAMED_QUERY_PATH).replace(':name', encodeURIComponent(name));
  const body = { parameters, response_format: responseFormat };
  if (sourceType) body.source_type = sourceType;
  return axios.post(url, body);
};

/**
 * Query the named-query catalog: each entry's `query` is the GQL text
 * already rendered for the current user (identity bindings resolved,
 * parameters filled with their declared examples) and executable as-is via
 * `executeOrbitQuery`. Null when the user cannot use Orbit.
 */
export const fetchOrbitTemplates = async (apollo) => {
  const { data } = await apollo.query({ query: orbitQueryTemplatesQuery });
  return data.orbit?.queryTemplates ?? null;
};

const toSchemaNode = (node) => ({
  name: node.name,
  domain: node.domain.name,
  description: node.description,
  primary_key: node.primaryKey,
  label_field: node.labelProperty,
  properties: node.properties.nodes.map((property) => ({
    name: property.name,
    data_type: property.dataType,
    nullable: property.nullable,
    enum_values: property.enumValues,
  })),
  style: node.display,
});

const toSchemaEdge = (edge) => ({
  name: edge.name,
  description: edge.description,
  variants: edge.endpoints.nodes.map(({ source, target }) => ({
    source_type: source.name,
    target_type: target.name,
  })),
});

/** Query the Orbit schema (node kinds and edge kinds). Null when the user cannot use Orbit. */
export const fetchOrbitSchema = async (apollo, { fetchPolicy } = {}) => {
  const { data } = await apollo.query({ query: orbitSchemaQuery, fetchPolicy });
  const schema = data.orbit?.schema;
  if (!schema) return null;

  return {
    nodes: schema.nodes.nodes.map(toSchemaNode),
    edges: schema.edges.nodes.map(toSchemaEdge),
  };
};
