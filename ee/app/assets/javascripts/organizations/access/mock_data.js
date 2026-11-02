/* eslint-disable @gitlab/require-i18n-strings -- Mock data */
import {
  ROLE_ARTIFACT_ADMIN,
  ROLE_ARTIFACT_MANAGER,
  ROLE_ARTIFACT_CONTRIBUTOR,
  ROLE_ARTIFACT_VIEWER,
} from './constants';

// Profiles link to `#` so the mock never points at a real GitLab.com account.
const mockAssignee = (id, name, username) => ({
  __typename: 'UserCore',
  id: `gid://gitlab/User/${id}`,
  name,
  username,
  webPath: '#',
  avatarUrl: null,
});

const mockAssignment = (assignee, role, createdAt) => ({
  __typename: 'ArtifactRegistryRoleAssignment',
  resourceId: '',
  role,
  createdAt,
  assignee,
});

export const MOCK_ROLE_ASSIGNMENTS = [
  mockAssignment(
    mockAssignee(1, 'Alex Garcia', 'agarcia'),
    ROLE_ARTIFACT_MANAGER,
    '2026-08-14T10:00:00Z',
  ),
  mockAssignment(
    mockAssignee(2, 'Priya Shah', 'pshah'),
    ROLE_ARTIFACT_MANAGER,
    '2026-09-01T14:30:00Z',
  ),
  mockAssignment(
    mockAssignee(3, 'Morgan Lee', 'mlee'),
    ROLE_ARTIFACT_ADMIN,
    '2026-09-05T08:20:00Z',
  ),
  mockAssignment(
    mockAssignee(4, 'Sam Rivera', 'srivera'),
    ROLE_ARTIFACT_CONTRIBUTOR,
    '2026-09-12T09:15:00Z',
  ),
  mockAssignment(
    mockAssignee(5, 'Jordan Kim', 'jkim'),
    ROLE_ARTIFACT_VIEWER,
    '2026-09-28T16:45:00Z',
  ),
];
