import { n__, s__ } from '~/locale';
import { artifactRegistryAccessOrganizationPath } from 'ee/lib/utils/path_helpers/organizations';

export const RESOURCE_ARTIFACT_REGISTRY = 'artifact-registry';

// Values match Types::Authz::ArtifactRegistry::RoleEnum so real API data needs no remap.
export const ROLE_ARTIFACT_ADMIN = 'ARTIFACT_ADMIN';
export const ROLE_ARTIFACT_MANAGER = 'ARTIFACT_MANAGER';
export const ROLE_ARTIFACT_CONTRIBUTOR = 'ARTIFACT_CONTRIBUTOR';
export const ROLE_ARTIFACT_VIEWER = 'ARTIFACT_VIEWER';

export const MAX_OWNERS = 3;
// Matches RoleAssignmentsResolver::MAX_PAGE_SIZE.
export const MAX_MEMBERS = 100;

export const TOKEN_TYPE_ROLE = 'role';

const can = (text) => ({ text, allowed: true });
const cannot = (text) => ({ text, allowed: false });

export const RESOURCES = {
  [RESOURCE_ARTIFACT_REGISTRY]: {
    key: RESOURCE_ARTIFACT_REGISTRY,
    label: s__('OrganizationAccess|Artifact Registry'),
    icon: 'infrastructure-registry',
    membersPath: artifactRegistryAccessOrganizationPath,
    adminRole: ROLE_ARTIFACT_ADMIN,
    ownerRole: ROLE_ARTIFACT_MANAGER,
    adminStatTitle: s__('OrganizationAccess|Artifact Admins'),
    adminFilterLabel: s__('OrganizationAccess|Filter list for Artifact Admins'),
    ownerStatTitle: s__('OrganizationAccess|Artifact Managers'),
    ownerFilterLabel: s__('OrganizationAccess|Filter list for Artifact Managers'),
    noMembersDescription: s__(
      'OrganizationAccess|Assign an Artifact role to a user to give them access to this resource.',
    ),
    defaultRole: ROLE_ARTIFACT_VIEWER,
    roles: [
      {
        value: ROLE_ARTIFACT_ADMIN,
        text: s__('OrganizationAccess|Artifact Admin'),
        description: s__('OrganizationAccess|Manage repository configuration and access.'),
        accessSummary: [
          can(s__('OrganizationAccess|Create and configure repositories')),
          can(s__('OrganizationAccess|Invite members and change their roles')),
          can(s__('OrganizationAccess|Remove members from Artifact Registry')),
        ],
        countText: (count) =>
          n__('OrganizationAccess|%{count} Admin', 'OrganizationAccess|%{count} Admins', count),
      },
      {
        value: ROLE_ARTIFACT_MANAGER,
        text: s__('OrganizationAccess|Artifact Manager'),
        description: s__('OrganizationAccess|Manage artifacts and repository configuration.'),
        accessSummary: [
          can(s__('OrganizationAccess|Everything an Artifact Contributor can do')),
          can(s__('OrganizationAccess|Delete artifacts')),
          can(s__('OrganizationAccess|Configure repositories')),
          cannot(s__('OrganizationAccess|Manage roles')),
        ],
        countText: (count) =>
          n__('OrganizationAccess|%{count} Manager', 'OrganizationAccess|%{count} Managers', count),
      },
      {
        value: ROLE_ARTIFACT_CONTRIBUTOR,
        text: s__('OrganizationAccess|Artifact Contributor'),
        description: s__('OrganizationAccess|Publish artifacts (for example, CI jobs).'),
        accessSummary: [
          can(s__('OrganizationAccess|Everything an Artifact Viewer can do')),
          can(s__('OrganizationAccess|Push and upload artifacts')),
          cannot(s__('OrganizationAccess|Delete artifacts')),
          cannot(s__('OrganizationAccess|Manage roles and settings')),
        ],
        countText: (count) =>
          n__(
            'OrganizationAccess|%{count} Contributor',
            'OrganizationAccess|%{count} Contributors',
            count,
          ),
      },
      {
        value: ROLE_ARTIFACT_VIEWER,
        text: s__('OrganizationAccess|Artifact Viewer'),
        description: s__('OrganizationAccess|Pull and browse artifacts.'),
        accessSummary: [
          can(
            s__(
              'OrganizationAccess|View the list of artifacts and repositories in Artifact Registry',
            ),
          ),
          can(s__('OrganizationAccess|View artifact metadata (tags, versions, size, upload date)')),
          can(
            s__(
              'OrganizationAccess|Download or pull artifacts (for example, Docker pulls or package installs)',
            ),
          ),
          cannot(s__('OrganizationAccess|Push, upload, or delete artifacts')),
          cannot(s__('OrganizationAccess|Manage roles and settings')),
        ],
        countText: (count) =>
          n__('OrganizationAccess|%{count} Viewer', 'OrganizationAccess|%{count} Viewers', count),
      },
    ],
  },
};
