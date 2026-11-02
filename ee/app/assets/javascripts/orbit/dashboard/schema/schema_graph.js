import { ENTITY_TYPE_ICONS, DEFAULT_NODE_COLOR } from 'ee/orbit/constants';
import { GQL_KEYWORDS } from '../query_editor/constants';
import { SCHEMA_DOMAINS, SCOPE_ENTITY, SCOPE_RELATIONSHIP } from './constants';

const QUERY_ROW_LIMIT = 25;
const STATUS_PROPERTY_NAMES = ['state', 'status'];
const RESERVED_ALIASES = new Set(
  GQL_KEYWORDS.flatMap((keyword) => keyword.toLowerCase().split(' ')),
);

export const RELATIONSHIP_DIRECTION = {
  OUTGOING: 'outgoing',
  INCOMING: 'incoming',
};

function entityStyle(node) {
  return {
    name: node.name,
    domain: node.domain,
    icon: ENTITY_TYPE_ICONS[node.name.toLowerCase()] || null,
    color: node.style?.color || DEFAULT_NODE_COLOR,
  };
}

export function normalizeSchema(schema) {
  return { ...schema, nodes: schema?.nodes || [], edges: schema?.edges || [] };
}

export function schemaDomains({ nodes }) {
  const domains = [...new Set(nodes.map((node) => node.domain))];
  const knownDomains = SCHEMA_DOMAINS.filter((domain) => domains.includes(domain.key));
  const unknownDomains = domains
    .filter((key) => !SCHEMA_DOMAINS.some((domain) => domain.key === key))
    .sort()
    .map((key) => ({ key, label: key }));

  return [...knownDomains, ...unknownDomains].map((domain) => {
    const entities = nodes.filter((node) => node.domain === domain.key).map(entityStyle);
    const entry =
      entities.find((entity) => entity.name.toLowerCase() === domain.entryType) || entities[0];

    return {
      key: domain.key,
      label: domain.label,
      icon: domain.icon || entry.icon,
      color: entry.color,
      entryEntity: entry.name,
      entities,
    };
  });
}

export function filterDomains(domains, search) {
  const term = search.trim().toLowerCase();
  if (!term) return domains;

  return domains
    .map((domain) =>
      domain.label.toLowerCase().includes(term)
        ? domain
        : {
            ...domain,
            entities: domain.entities.filter((entity) => entity.name.toLowerCase().includes(term)),
          },
    )
    .filter((domain) => domain.entities.length);
}

export function itemCount(itemCounts, name) {
  return itemCounts?.[name.toLowerCase()] ?? null;
}

function relationshipVariants({ nodes, edges }) {
  const nodeNames = new Set(nodes.map((node) => node.name));
  return edges
    .flatMap((edge) =>
      (edge.variants || []).map((variant) => ({
        edge: edge.name,
        description: edge.description,
        source: variant.source_type,
        target: variant.target_type,
      })),
    )
    .filter(({ source, target }) => nodeNames.has(source) && nodeNames.has(target));
}

export function entityRelationships(schema, name) {
  const variants = relationshipVariants(schema);

  return {
    outgoing: variants
      .filter(({ source }) => source === name)
      .map(({ edge, description, target }) => ({ edge, description, entity: target })),
    incoming: variants
      .filter(({ source, target }) => target === name && source !== name)
      .map(({ edge, description, source }) => ({ edge, description, entity: source })),
  };
}

export function groupByEntity(relationships) {
  const groups = relationships.reduce((map, { entity, edge, description }) => {
    const edges = map.get(entity) || new Map();
    return map.set(entity, edges.set(edge, description));
  }, new Map());

  return [...groups.entries()].map(([entity, edges]) => ({
    entity,
    edges: [...edges.entries()].map(([edge, description]) => ({ name: edge, description })),
  }));
}

export function connectedEntities({ outgoing, incoming }, name) {
  const isScopeRelationship = (relationship) =>
    name === SCOPE_ENTITY && relationship.edge === SCOPE_RELATIONSHIP;
  const listedIncoming = incoming.filter((relationship) => !isScopeRelationship(relationship));

  return {
    rows: [
      ...groupByEntity(outgoing).map((row) => ({
        ...row,
        direction: RELATIONSHIP_DIRECTION.OUTGOING,
      })),
      ...groupByEntity(listedIncoming).map((row) => ({
        ...row,
        direction: RELATIONSHIP_DIRECTION.INCOMING,
      })),
    ],
    scopedEntities: [...new Set(incoming.filter(isScopeRelationship).map(({ entity }) => entity))],
  };
}

export function entityPairs(schema) {
  const pairs = relationshipVariants(schema).reduce((byKey, { edge, source, target }) => {
    const [first, second] = [source, target].sort();
    const key = `${first}|${second}`;
    const pair = byKey.get(key) || { key, first, second, relationships: [] };
    pair.relationships.push({ name: edge, source, target });
    return byKey.set(key, pair);
  }, new Map());

  return [...pairs.values()];
}

function isScopeOnlyPair(pair) {
  return pair.relationships.every(({ name }) => name === SCOPE_RELATIONSHIP);
}

export function restingPairKeys(pairs, domainByEntity) {
  const scopeDomain = domainByEntity[SCOPE_ENTITY];
  const linkedPairs = pairs.filter((pair) => !isScopeOnlyPair(pair));
  const domainsLinkedToScope = new Set(
    linkedPairs
      .map(({ first, second }) => [domainByEntity[first], domainByEntity[second]])
      .filter((domains) => domains.includes(scopeDomain))
      .flat(),
  );
  const scopePairs = pairs.filter(isScopeOnlyPair).filter((pair) => {
    const domain = domainByEntity[pair.first === SCOPE_ENTITY ? pair.second : pair.first];
    if (domainsLinkedToScope.has(domain)) return false;

    domainsLinkedToScope.add(domain);
    return true;
  });

  return new Set([...linkedPairs, ...scopePairs].map(({ key }) => key));
}

const LABEL_POSITIONS = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8];

function boxesOverlap(a, b) {
  return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
}

function labelBoxAt({ segment, width, height }, position) {
  const x = segment.x1 + (segment.x2 - segment.x1) * position;
  const y = segment.y1 + (segment.y2 - segment.y1) * position;
  return {
    x,
    y,
    left: x - width / 2,
    right: x + width / 2,
    top: y - height / 2,
    bottom: y + height / 2,
  };
}

export function placeEdgeLabels(labels, obstacles) {
  return labels.reduce((placed, label) => {
    const taken = [...obstacles, ...placed.map(({ box }) => box)];
    const box = LABEL_POSITIONS.map((position) => labelBoxAt(label, position)).find(
      (candidate) => !taken.some((other) => boxesOverlap(candidate, other)),
    );
    return box ? [...placed, { ...label, box }] : placed;
  }, []);
}

export function edgeSegment(from, to, { fromGap, toGap }) {
  const distance = Math.hypot(to.x - from.x, to.y - from.y);
  const unitX = (to.x - from.x) / distance;
  const unitY = (to.y - from.y) / distance;

  return {
    x1: from.x + unitX * fromGap,
    y1: from.y + unitY * fromGap,
    x2: to.x - unitX * toGap,
    y2: to.y - unitY * toGap,
    length: Math.max(distance - fromGap - toGap, 0),
  };
}

function arrowheadPoints({ x1, y1, x2, y2 }, size) {
  const angle = Math.atan2(y2 - y1, x2 - x1);
  const corner = (offset) =>
    `${x2 - size * Math.cos(angle + offset)},${y2 - size * Math.sin(angle + offset)}`;

  return [`${x2},${y2}`, corner(Math.PI / 7), corner(-Math.PI / 7)].join(' ');
}

export function edgeArrowheads(segment, relationships, { start, end, size }) {
  const reversed = { x1: segment.x2, y1: segment.y2, x2: segment.x1, y2: segment.y1 };

  return [
    relationships.some(({ target }) => target === end) && arrowheadPoints(segment, size),
    relationships.some(({ target }) => target === start) && arrowheadPoints(reversed, size),
  ].filter(Boolean);
}

function queryAlias(name, takenAliases = []) {
  const initials = name.replace(/[^A-Z]/g, '').toLowerCase();
  let alias = initials;
  let suffix = 2;
  while (RESERVED_ALIASES.has(alias) || takenAliases.includes(alias)) {
    alias = `${initials}${suffix}`;
    suffix += 1;
  }
  return alias;
}

function statusProperty(node) {
  return (node.properties || []).find(
    (property) => STATUS_PROPERTY_NAMES.includes(property.name) && property.enum_values?.length,
  );
}

/* eslint-disable @gitlab/require-i18n-strings -- GQL code, not UI text */
// The server rejects a MATCH with no filter on any node, so each query filters on the
// primary key, which every entity has.
function primaryKeyFilter(alias, node) {
  return `WHERE ${alias}.${node.primary_key} IS NOT NULL`;
}

export function entityQuery(node) {
  const alias = queryAlias(node.name);
  const columns = [...new Set([node.label_field, statusProperty(node)?.name])].filter(Boolean);

  return [
    `MATCH (${alias}:${node.name})`,
    primaryKeyFilter(alias, node),
    `RETURN ${columns.map((column) => `${alias}.${column}`).join(', ')}`,
    `LIMIT ${QUERY_ROW_LIMIT}`,
  ].join('\n');
}

export function relationshipQuery({ name, source, target }, nodesByName) {
  const sourceAlias = queryAlias(source);
  const targetAlias = queryAlias(target, [sourceAlias]);

  return [
    `MATCH (${sourceAlias}:${source})-[:${name}]->(${targetAlias}:${target})`,
    primaryKeyFilter(sourceAlias, nodesByName[source]),
    `RETURN ${sourceAlias}.${nodesByName[source].label_field}, ${targetAlias}.${nodesByName[target].label_field}`,
    `LIMIT ${QUERY_ROW_LIMIT}`,
  ].join('\n');
}
/* eslint-enable @gitlab/require-i18n-strings */
