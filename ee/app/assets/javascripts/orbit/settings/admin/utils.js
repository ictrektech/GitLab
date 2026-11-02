import { s__ } from '~/locale';
import { STATUS_UNKNOWN } from '../../constants';
import { INDEXING_STATE } from '../../shared/groups/constants';
import { hasIndexingError } from '../../shared/groups/utils';

export function groupNote(group) {
  if (group.failure) return group.failure.message;
  if (hasIndexingError(group)) {
    return s__(
      'Orbit|GitLab Orbit could not index this group. Check the GitLab Orbit indexer logs.',
    );
  }
  if (!group.isOn) return null;
  if (group.indexingState === INDEXING_STATE.UNKNOWN) {
    return s__('Orbit|GitLab Orbit has not reported a status for this group yet.');
  }
  if (group.isExcluded) {
    return s__('Orbit|This group is excluded, so GitLab Orbit turns off for it within an hour.');
  }

  return null;
}

export function buildGroupRows({ groups, excludedPaths, failures, allowedActions }) {
  return groups.map((group) => {
    const row = {
      id: group.id,
      name: group.name,
      fullPath: group.fullPath,
      webPath: group.webPath,
      avatarUrl: group.avatarUrl,
      allowedActions,
      isOn: Boolean(group.orbit?.enabled),
      isExcluded: excludedPaths.has(group.fullPath),
      indexingState: group.orbit?.indexing?.state ?? null,
      indexingAreas: group.orbit?.indexing?.areas ?? [],
      enabledAt: group.orbit?.enabledAt ?? null,
      failure: failures[group.fullPath] ?? null,
    };

    return { ...row, note: groupNote(row) };
  });
}

export function filterGroupsBySearch(groups, search) {
  const term = search.toLowerCase();
  return groups.filter(
    (group) =>
      group.name.toLowerCase().includes(term) || group.fullPath.toLowerCase().includes(term),
  );
}

const UNKNOWN_SERVICE_STATUS = { state: STATUS_UNKNOWN, version: null, components: [] };

export function statusFromServiceStatus(serviceStatus) {
  const { state, version, components } = serviceStatus ?? UNKNOWN_SERVICE_STATUS;
  return { overall: state, version, components };
}
