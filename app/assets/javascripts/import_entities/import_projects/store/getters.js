import { isProjectImportable, isIncompatible, isImporting } from '../utils';

export const importingRepoCount = (state) =>
  state.repositories.filter((repo) => isImporting(repo)).length;

export const isImportingAnyRepo = (state) => state.repositories.some((repo) => isImporting(repo));

export const hasIncompatibleRepos = (state) =>
  state.repositories.some((repo) => isIncompatible(repo));

export const hasImportableRepos = (state) =>
  state.repositories.some((repo) => isProjectImportable(repo));

export const importAllCount = (state) =>
  state.repositories.filter((repo) => isProjectImportable(repo)).length;

export const getImportTarget = (state) => (repoId) => {
  if (state.customImportTargets[repoId]) {
    return state.customImportTargets[repoId];
  }

  const repo = state.repositories.find((r) => r.importSource.id === repoId);

  return {
    newName: repo.importSource.sanitizedName,
    targetNamespace: state.defaultTargetNamespace,
  };
};
