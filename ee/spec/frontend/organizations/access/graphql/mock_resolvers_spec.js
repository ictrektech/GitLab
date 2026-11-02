import { createMockResolvers } from 'ee/organizations/access/graphql/mock_resolvers';

const assignment = (role) => ({ __typename: 'ArtifactRegistryRoleAssignment', role });

describe('Organization Access mock resolvers', () => {
  const assignments = [
    assignment('ARTIFACT_MANAGER'),
    assignment('ARTIFACT_MANAGER'),
    assignment('ARTIFACT_VIEWER'),
  ];
  const { Query } = createMockResolvers(assignments);

  it('counts every role, including roles with no assignments', () => {
    const counts = Query.artifactRegistryRoleAssignmentCounts();

    expect(counts.total).toBe(3);
    expect(counts.byRole.map(({ role, count }) => [role, count])).toEqual([
      ['ARTIFACT_ADMIN', 0],
      ['ARTIFACT_MANAGER', 2],
      ['ARTIFACT_CONTRIBUTOR', 0],
      ['ARTIFACT_VIEWER', 1],
    ]);
  });

  it('filters assignments by role and limits them with first', () => {
    const { nodes, pageInfo } = Query.artifactRegistryRoleAssignments(null, {
      roles: ['ARTIFACT_MANAGER'],
      first: 1,
    });

    expect(nodes).toEqual([assignments[0]]);
    expect(pageInfo.hasNextPage).toBe(true);
  });

  it('returns every assignment without a role filter or first', () => {
    expect(Query.artifactRegistryRoleAssignments(null, {}).nodes).toEqual(assignments);
  });
});
