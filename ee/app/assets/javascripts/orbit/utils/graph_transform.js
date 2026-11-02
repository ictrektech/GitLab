// Transforms raw Orbit API responses into graph-ready node/edge structures.
import { isEmpty, isPlainObject } from 'lodash-es';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { ENTITY_TYPE_COLORS, ENTITY_TYPE_NAMES } from '../constants';

const GROUP_NODE_TYPE = 'Group';

function toGraphId(type, id) {
  return `${type}_${id}`;
}

export function toGroupGraphNode(group) {
  const numericId = getIdFromGraphQLId(group.id);
  const enabled = Boolean(group.orbit?.enabled);

  return {
    id: toGraphId(GROUP_NODE_TYPE, numericId),
    type: 'group',
    label: group.name,
    domain: 'project',
    color: ENTITY_TYPE_COLORS.group,
    entityName: ENTITY_TYPE_NAMES.group,
    avatarUrl: group.avatarUrl,
    knowledgeGraphEnabled: enabled,
    properties: {
      id: numericId,
      name: group.name,
      full_name: group.fullName,
      full_path: group.fullPath,
      knowledge_graph_enabled: enabled,
    },
  };
}

/** Parses a composite graph ID back into { type, id }. */
export function parseGraphId(graphId) {
  const idx = graphId.indexOf('_');
  if (idx === -1) return { type: graphId, id: graphId };
  return { type: graphId.slice(0, idx), id: graphId.slice(idx + 1) };
}

function nodeLabel(properties, labelField) {
  if (labelField && properties[labelField]) return String(properties[labelField]);
  return (
    properties.name ||
    properties.title ||
    properties.username ||
    properties.full_path ||
    String(properties.id ?? '')
  );
}

/**
 * First step after a query: converts raw API nodes/edges into indexed
 * graph format with styled labels. Returns a nodeMap for edge resolution.
 */
export function transformGraphResponse(response, nodeStyleMap = {}) {
  const { nodes: rawNodes = [], edges: rawEdges = [] } = response;

  const nodeMap = new Map();
  const nodes = rawNodes.map((node, i) => {
    const { type: entityType, id, ...properties } = node;
    const key = (entityType || 'unknown').toLowerCase();
    const style = nodeStyleMap[key] || {};
    const gid = toGraphId(entityType, id);
    nodeMap.set(gid, i);

    return {
      id: gid,
      label: nodeLabel(properties, style.labelField),
      type: key,
      domain: style.domain || null,
      properties: { id, ...properties },
    };
  });

  const edges = [];
  for (const edge of rawEdges) {
    const source = nodeMap.get(toGraphId(edge.from, edge.from_id));
    const target = nodeMap.get(toGraphId(edge.to, edge.to_id));
    if (source !== undefined && target !== undefined) {
      edges.push({ source, target, type: edge.type });
    }
  }

  return { nodes, edges, nodeMap };
}

/**
 * Called on node expansion: merges neighbor response into existing graph,
 * deduplicating by ID. Returns only the new nodes and edges to append.
 */
export function mergeNeighborNodes(response, graphNodes, nodeStyleMap = {}) {
  const { nodes: respNodes = [], edges: respEdges = [] } = response;
  const existingIds = new Set(graphNodes.map((n) => n.id));
  const localMap = new Map();
  const newNodes = [];
  const newEdges = [];

  for (const rn of respNodes) {
    if (!rn.type) {
      localMap.set(toGraphId('undefined', rn.id), -1);
    } else {
      const gid = toGraphId(rn.type, rn.id);
      if (!localMap.has(gid)) {
        const existingIdx = graphNodes.findIndex((n) => n.id === gid);
        if (existingIdx >= 0) {
          localMap.set(gid, existingIdx);
        } else {
          const key = rn.type.toLowerCase();
          const style = nodeStyleMap[key] || {};
          const { type: _type, id, ...properties } = rn;
          localMap.set(gid, graphNodes.length + newNodes.length);
          existingIds.add(gid);
          newNodes.push({
            id: gid,
            label: nodeLabel(properties, style.labelField),
            type: key,
            domain: style.domain || null,
            properties: { id, ...properties },
          });
        }
      }
    }
  }

  for (const edge of respEdges) {
    const source = localMap.get(toGraphId(edge.from, edge.from_id));
    const target = localMap.get(toGraphId(edge.to, edge.to_id));
    if (source !== undefined && target !== undefined && source >= 0 && source !== target) {
      newEdges.push({ source, target, type: edge.type });
    }
  }

  return { newNodes, newEdges };
}

export function graphNodesToRows(graphNodes) {
  return graphNodes.map((node) => {
    const { type } = parseGraphId(node.id);
    return { type, ...(node.properties || {}) };
  });
}

function flattenCell([key, value]) {
  if (!isPlainObject(value)) return [[key, value]];
  if (isEmpty(value.properties)) return [[key, value.id ?? '']];

  return [
    [`${key}.id`, value.id],
    ...Object.entries(value.properties).map(([name, cell]) => [`${key}.${name}`, cell]),
  ];
}

export function aggregationRowsToTable(rows) {
  return (Array.isArray(rows) ? rows : []).map((row) =>
    Object.fromEntries(Object.entries(row).flatMap(flattenCell)),
  );
}
