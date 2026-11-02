import {
  CLUSTER_CELL_HEIGHT_PX,
  CLUSTER_CELL_WIDTH_PX,
  CLUSTER_GAP_PX,
  CLUSTER_WIDTH_FACTOR,
  GRAPH_MARGIN_X_PX,
  GRAPH_MARGIN_Y_PX,
  RING_ASPECT_RATIO,
  RING_STEP_PX,
  SCOPE_ENTITY,
  SCOPE_RELATIONSHIP,
} from './constants';

const MAX_RING_STEPS = 200;

const countBy = (keys) =>
  keys.reduce((counts, key) => counts.set(key, (counts.get(key) ?? 0) + 1), new Map());
const domainPairKey = (a, b) => [a, b].sort().join('|');

const isScopePillCell = ({ x, y }) => x === 0 && y === CLUSTER_CELL_HEIGHT_PX;
const CORE_CENTER = { x: 0, y: 0 };
const ringDistance = (a, b = CORE_CENTER) => Math.hypot(a.x - b.x, (a.y - b.y) / RING_ASPECT_RATIO);
const byRingDistance = (a, b) => ringDistance(a) - ringDistance(b);

function cellBounds(cells) {
  const xs = cells.map(({ x }) => x);
  const ys = cells.map(({ y }) => y);
  return {
    left: Math.min(...xs) - CLUSTER_CELL_WIDTH_PX / 2,
    right: Math.max(...xs) + CLUSTER_CELL_WIDTH_PX / 2,
    top: Math.min(...ys) - CLUSTER_CELL_HEIGHT_PX / 2,
    bottom: Math.max(...ys) + CLUSTER_CELL_HEIGHT_PX / 2,
  };
}

function gridCells(columns, rows) {
  return Array.from({ length: columns * rows }, (_, index) => ({
    x: ((index % columns) - (columns - 1) / 2) * CLUSTER_CELL_WIDTH_PX,
    y: (Math.floor(index / columns) - (rows - 1) / 2) * CLUSTER_CELL_HEIGHT_PX,
  }));
}

function coreCells(count) {
  const side = Math.ceil(Math.sqrt(count + 1));
  const columns = side % 2 ? side : side + 1;

  return gridCells(columns, columns)
    .filter((cell) => !isScopePillCell(cell))
    .sort(byRingDistance)
    .slice(0, count);
}

function ringCells(count, angle) {
  const isBesideCore = Math.abs(Math.cos(angle)) > Math.abs(Math.sin(angle));
  const widthFactor = isBesideCore ? 1 / CLUSTER_WIDTH_FACTOR : CLUSTER_WIDTH_FACTOR;
  const columns = Math.min(count, Math.ceil(Math.sqrt(count * widthFactor)));

  return gridCells(columns, Math.ceil(count / columns));
}

function boxesOverlap(a, b) {
  return (
    a.x + a.bounds.left < b.x + b.bounds.right + CLUSTER_GAP_PX &&
    b.x + b.bounds.left < a.x + a.bounds.right + CLUSTER_GAP_PX &&
    a.y + a.bounds.top < b.y + b.bounds.bottom + CLUSTER_GAP_PX &&
    b.y + b.bounds.top < a.y + a.bounds.bottom + CLUSTER_GAP_PX
  );
}

function ringGap(a, b, count) {
  const steps = Math.abs(a - b);
  return Math.min(steps, count - steps);
}

function swapped(order, i, j) {
  const next = [...order];
  [next[i], next[j]] = [next[j], next[i]];
  return next;
}

function moved(order, from, to) {
  const next = order.filter((_, index) => index !== from);
  next.splice(to, 0, order[from]);
  return next;
}

function neighbourOrders(order) {
  return order.flatMap((_, i) =>
    order.flatMap((__, j) => (i === j ? [] : [swapped(order, i, j), moved(order, i, j)])),
  );
}

function bestOrder(order, cost) {
  const best = neighbourOrders(order).reduce(
    (current, next) => (cost(next) < cost(current) ? next : current),
    order,
  );
  return best === order ? order : bestOrder(best, cost);
}

function ringOrder(domains, linksBetween) {
  const cost = (order) =>
    order
      .flatMap((a, i) =>
        order
          .slice(i + 1)
          .map((b, offset) => linksBetween(a, b) * ringGap(i, i + 1 + offset, order.length)),
      )
      .reduce((sum, pairCost) => sum + pairCost, 0);

  return bestOrder(domains, cost);
}

function clusterAt(cluster, radius) {
  return {
    ...cluster,
    x: radius * Math.cos(cluster.angle),
    y: radius * RING_ASPECT_RATIO * Math.sin(cluster.angle),
  };
}

function ringAroundCore(core, domains, domainLinks) {
  const linksBetween = (a, b) => domainLinks.get(domainPairKey(a.key, b.key)) ?? 0;
  const radii = Array.from({ length: MAX_RING_STEPS }, (_, step) => step * RING_STEP_PX);
  const clusters = ringOrder(domains, linksBetween).map((domain, index, order) => {
    const angle = -Math.PI / 2 + (index * 2 * Math.PI) / order.length;
    const cells = ringCells(domain.entities.length, angle);
    return { ...domain, angle, cells, bounds: cellBounds(cells) };
  });

  return clusters.reduce((placed, cluster) => {
    const fits = (candidate) => [core, ...placed].every((other) => !boxesOverlap(candidate, other));
    const radius =
      radii.find((candidate) => fits(clusterAt(cluster, candidate))) ?? radii[radii.length - 1];
    return [...placed, clusterAt(cluster, radius)];
  }, []);
}

function placeCluster({ entities, cells, x, y }, rank) {
  const ranked = [...entities].sort((a, b) => rank(b) - rank(a));
  const nearestCoreFirst = cells
    .map((cell) => ({ x: x + cell.x, y: y + cell.y }))
    .sort(byRingDistance);

  return ranked.map(({ name }, index) => [name, nearestCoreFirst[index]]);
}

function layoutWithMargins(entries) {
  const xs = entries.map(([, { x }]) => x);
  const ys = entries.map(([, { y }]) => y);
  const left = Math.min(...xs) - GRAPH_MARGIN_X_PX;
  const top = Math.min(...ys) - GRAPH_MARGIN_Y_PX;

  return {
    positions: Object.fromEntries(
      entries.map(([name, { x, y }]) => [name, { x: x - left, y: y - top }]),
    ),
    width: Math.max(...xs) + GRAPH_MARGIN_X_PX - left,
    height: Math.max(...ys) + GRAPH_MARGIN_Y_PX - top,
  };
}

const EMPTY_LAYOUT = {
  positions: {},
  width: GRAPH_MARGIN_X_PX * 2,
  height: GRAPH_MARGIN_Y_PX * 2,
};

function crossDomainLinks(pairs, domainByEntity) {
  const crossDomainPairs = pairs.filter(
    ({ first, second, relationships }) =>
      domainByEntity[first] !== domainByEntity[second] &&
      relationships.some(({ name }) => name !== SCOPE_RELATIONSHIP),
  );

  return {
    entityLinks: countBy(crossDomainPairs.flatMap(({ first, second }) => [first, second])),
    domainLinks: countBy(
      crossDomainPairs.map(({ first, second }) =>
        domainPairKey(domainByEntity[first], domainByEntity[second]),
      ),
    ),
  };
}

function coreCluster(domain) {
  const cells = coreCells(domain.entities.length);
  return { ...domain, cells, bounds: cellBounds(cells), ...CORE_CENTER };
}

export function entityLayout(domains, pairs) {
  if (!domains.length) return EMPTY_LAYOUT;

  const domainByEntity = Object.fromEntries(
    domains.flatMap(({ key, entities }) => entities.map(({ name }) => [name, key])),
  );
  const { entityLinks, domainLinks } = crossDomainLinks(pairs, domainByEntity);
  const rank = ({ name }) => (name === SCOPE_ENTITY ? Infinity : (entityLinks.get(name) ?? 0));

  const coreKey = domainByEntity[SCOPE_ENTITY] ?? domains[0].key;
  const core = coreCluster(domains.find(({ key }) => key === coreKey));
  const ring = ringAroundCore(
    core,
    domains.filter(({ key }) => key !== coreKey),
    domainLinks,
  );

  return layoutWithMargins([core, ...ring].flatMap((cluster) => placeCluster(cluster, rank)));
}
