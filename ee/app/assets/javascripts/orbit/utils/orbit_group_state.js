import { INDEXING_START_TIMEOUT_MS, RECENTLY_ENABLED_MS } from '../constants';

const STATE_READY = 'READY';
const STATE_INDEXING = 'INDEXING';
const STATE_NOT_STARTED = 'NOT_STARTED';
// Orbit also counts per-project code indexing in this area, so it indexes again for every new project.
const SOURCE_CODE_AREA = 'source_code';

export const isOrbitReady = (group) => group.orbit?.indexing?.state === STATE_READY;

const isEnabledWithin = (group, windowMs) => {
  const enabledAt = group.orbit?.enabledAt;
  return Boolean(enabledAt) && Date.now() - new Date(enabledAt).getTime() <= windowMs;
};

export const isIndexingQueued = (group) =>
  !group.orbit?.indexing && !isEnabledWithin(group, RECENTLY_ENABLED_MS);

// Orbit keeps an area ready once its first backfill completes, so this stays true afterwards.
const isSdlcIndexed = (group) => {
  const sdlcAreas = (group.orbit?.indexing?.areas ?? []).filter(
    ({ name }) => name !== SOURCE_CODE_AREA,
  );
  return sdlcAreas.length > 0 && sdlcAreas.every(({ state }) => state === STATE_READY);
};

export const isInitialIndexing = (group) => {
  const state = group.orbit?.indexing?.state;
  return (
    (state === STATE_INDEXING && !isSdlcIndexed(group)) ||
    (state === STATE_NOT_STARTED && isEnabledWithin(group, INDEXING_START_TIMEOUT_MS))
  );
};

export const pendingProjectCount = (group) => {
  const indexing = group.orbit?.indexing;
  if (indexing?.state !== STATE_INDEXING || !isSdlcIndexed(group)) return 0;

  const projects = indexing.projects ?? {};
  return Math.max((projects.totalKnown ?? 0) - (projects.indexed ?? 0) - (projects.gaps ?? 0), 0);
};

export const hasPendingProjects = (group) => pendingProjectCount(group) > 0;

const indexingVersion = (group) => {
  const indexing = group.orbit?.indexing;
  const areaStates = (indexing?.areas ?? []).map(({ name, state }) => `${name}=${state}`);

  return [indexing?.state, ...areaStates].join(':');
};

export const groupsIndexingVersion = (groups) =>
  groups.map((group) => `${group.fullPath}:${indexingVersion(group)}`).join('|');

export const sumItemCounts = (groups) => {
  const totals = { domains: {}, entities: {} };

  groups
    .flatMap((group) => group.orbit?.itemCounts?.domains ?? [])
    .forEach(({ name: domain, entities }) =>
      (entities ?? []).forEach(({ name, count }) => {
        const entity = name.toLowerCase();
        totals.domains[domain] = (totals.domains[domain] ?? 0) + Number(count);
        totals.entities[entity] = (totals.entities[entity] ?? 0) + Number(count);
      }),
    );

  return totals;
};
