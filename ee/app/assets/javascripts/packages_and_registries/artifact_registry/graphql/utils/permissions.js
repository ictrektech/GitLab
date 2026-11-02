import {
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
  REPOSITORY_PERMISSION_DELETE_REPOSITORY_UPSTREAM,
  REPOSITORY_PERMISSION_UPDATE_REPOSITORY,
} from 'ee/packages_and_registries/artifact_registry/constants';

export const permissionAllows = (block, action) => block?.[action] === true;

export const upstreamActions = ({ kind, userPermissions }, repositoryPermissions) => ({
  clearCache:
    kind === REPOSITORY_KIND_REMOTE &&
    permissionAllows(userPermissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT),
  edit: permissionAllows(userPermissions, REPOSITORY_PERMISSION_UPDATE_REPOSITORY),
  remove: permissionAllows(repositoryPermissions, REPOSITORY_PERMISSION_DELETE_REPOSITORY_UPSTREAM),
});

export const upstreamHasActions = (upstreamRepository, repositoryPermissions) =>
  Object.values(upstreamActions(upstreamRepository, repositoryPermissions)).some(Boolean);
