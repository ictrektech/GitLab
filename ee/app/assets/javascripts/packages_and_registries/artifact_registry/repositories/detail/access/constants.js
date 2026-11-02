import { s__ } from '~/locale';

export const ROLE_NAMES = {
  ARTIFACT_VIEWER: s__('ArtifactRegistry|Artifact Viewer'),
  ARTIFACT_CONTRIBUTOR: s__('ArtifactRegistry|Artifact Contributor'),
  ARTIFACT_MANAGER: s__('ArtifactRegistry|Artifact Manager'),
  ARTIFACT_ADMIN: s__('ArtifactRegistry|Artifact Admin'),
};

export const ROLE_ASSIGNMENTS_PAGE_SIZE = 100;

export const ROLE_ASSIGNMENTS_ERROR_DENIED = 'denied';

export const ROLE_ASSIGNMENTS_ERROR_UNAVAILABLE = 'unavailable';

export const ROLE_ASSIGNMENTS_ERROR_INVALID_REQUEST = 'invalid_request';

export const ROLE_ASSIGNMENTS_ERROR_UNKNOWN = 'unknown';
