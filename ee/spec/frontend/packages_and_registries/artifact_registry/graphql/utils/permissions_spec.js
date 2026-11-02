import {
  permissionAllows,
  upstreamActions,
  upstreamHasActions,
} from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';

describe('permissionAllows', () => {
  it('is true on an explicit true', () => {
    expect(permissionAllows({ updateRepository: true }, 'updateRepository')).toBe(true);
  });

  it.each([undefined, null, true, 'allowed'])('is false for an unresolved block, %p', (block) => {
    expect(permissionAllows(block, 'updateRepository')).toBe(false);
  });

  it.each([false, null, undefined, 'true', 1, {}])('is false for a verdict of %p', (verdict) => {
    expect(permissionAllows({ updateRepository: verdict }, 'updateRepository')).toBe(false);
  });

  it('is false for an action the block does not carry', () => {
    expect(permissionAllows({ deleteRepository: true }, 'updateRepository')).toBe(false);
  });
});

describe('upstreamActions', () => {
  const allowed = { updateRepository: true, deleteArtifact: true, deleteRepositoryUpstream: true };

  it('allows every action on a remote upstream whose verdicts all allow', () => {
    expect(upstreamActions({ kind: 'REMOTE', userPermissions: allowed }, allowed)).toEqual({
      clearCache: true,
      edit: true,
      remove: true,
    });
  });

  it('never allows Clear cache on a hosted upstream', () => {
    expect(upstreamActions({ kind: 'HOSTED', userPermissions: allowed }, allowed)).toEqual({
      clearCache: false,
      edit: true,
      remove: true,
    });
  });

  it('reads Remove from the page repository, not the upstream', () => {
    expect(
      upstreamActions(
        { kind: 'REMOTE', userPermissions: allowed },
        { deleteRepositoryUpstream: false },
      ).remove,
    ).toBe(false);
    expect(
      upstreamActions(
        { kind: 'REMOTE', userPermissions: { deleteRepositoryUpstream: false } },
        { deleteRepositoryUpstream: true },
      ).remove,
    ).toBe(true);
  });

  it('allows nothing when neither verdict block arrived', () => {
    expect(upstreamActions({ kind: 'REMOTE', userPermissions: null }, null)).toEqual({
      clearCache: false,
      edit: false,
      remove: false,
    });
  });
});

describe('upstreamHasActions', () => {
  it.each`
    kind        | userPermissions               | repositoryPermissions                 | expected
    ${'REMOTE'} | ${{ deleteArtifact: true }}   | ${null}                               | ${true}
    ${'HOSTED'} | ${{ deleteArtifact: true }}   | ${null}                               | ${false}
    ${'HOSTED'} | ${{ updateRepository: true }} | ${null}                               | ${true}
    ${'HOSTED'} | ${null}                       | ${{ deleteRepositoryUpstream: true }} | ${true}
    ${'REMOTE'} | ${null}                       | ${null}                               | ${false}
  `(
    'is $expected for a $kind upstream allowing $userPermissions under $repositoryPermissions',
    ({ kind, userPermissions, repositoryPermissions, expected }) => {
      expect(upstreamHasActions({ kind, userPermissions }, repositoryPermissions)).toBe(expected);
    },
  );
});
