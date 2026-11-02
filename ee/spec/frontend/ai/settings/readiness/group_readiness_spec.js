import {
  isLocked,
  lockingGroup,
  readinessSummary,
  stepStatus,
} from 'ee/ai/settings/readiness/group_readiness';

const ALL_ON = {
  duoOn: true,
  platformOn: true,
  agentsOn: true,
  flowsOn: true,
  platformOffAtOwner: false,
  runnerConfirmed: true,
  isSaaS: true,
  rootAncestorName: 'my-group',
};

const LOCKED_BY_GROUP = { duoLockedBy: 'my-group', flowsLockedBy: 'my-group' };

describe('readinessSummary', () => {
  it.each`
    scenario                            | steps                                                             | stateLine                                                                            | progressLabel       | status             | doneCount
    ${'everything on'}                  | ${{}}                                                             | ${'Agents and flows are ready in this group.'}                                       | ${'Setup complete'} | ${'complete'}      | ${4}
    ${'everything on, no runner'}       | ${{ runnerConfirmed: false }}                                     | ${"Agents work now. Flows are on, but they won't start until you connect a runner."} | ${'Runner needed'}  | ${'runner-needed'} | ${4}
    ${'flows off'}                      | ${{ flowsOn: false }}                                             | ${'Agents work now. 1 more step to set up flows.'}                                   | ${'1 step left'}    | ${'partial'}       | ${3}
    ${'flows off, no runner'}           | ${{ flowsOn: false, runnerConfirmed: false }}                     | ${'Agents work now. 1 more step to set up flows.'}                                   | ${'1 step left'}    | ${'partial'}       | ${3}
    ${'agents off'}                     | ${{ agentsOn: false }}                                            | ${'Flows work now. 1 more step to set up agents.'}                                   | ${'1 step left'}    | ${'partial'}       | ${3}
    ${'agents and flows off'}           | ${{ agentsOn: false, flowsOn: false }}                            | ${'Nothing is turned on yet. 2 steps left to set up agents and flows.'}              | ${'2 steps left'}   | ${'partial'}       | ${2}
    ${'platform off at this group'}     | ${{ platformOn: false }}                                          | ${'Turn on the Agent Platform to get started.'}                                      | ${'1 step left'}    | ${'partial'}       | ${3}
    ${'GitLab Duo off'}                 | ${{ duoOn: false }}                                               | ${'Turn on GitLab Duo to get started.'}                                              | ${'1 step left'}    | ${'partial'}       | ${3}
    ${'GitLab Duo and platform off'}    | ${{ duoOn: false, platformOn: false }}                            | ${'Turn on GitLab Duo and the Agent Platform to get started.'}                       | ${'2 steps left'}   | ${'partial'}       | ${2}
    ${'platform off at the root group'} | ${{ platformOn: false, platformOffAtOwner: true }}                | ${'Agent Platform is off for my-group.'}                                             | ${'Blocked'}        | ${'blocked'}       | ${3}
    ${'platform off at the instance'}   | ${{ platformOn: false, platformOffAtOwner: true, isSaaS: false }} | ${'Agent Platform is off for this instance.'}                                        | ${'Blocked'}        | ${'blocked'}       | ${3}
  `('describes $scenario', ({ steps, stateLine, progressLabel, status, doneCount }) => {
    expect(readinessSummary({ ...ALL_ON, ...steps })).toEqual({
      stateLine,
      lockedNote: '',
      progressLabel,
      status,
      doneCount,
      progressBarLabel: `Agent setup progress: ${doneCount} of 4 steps complete`,
    });
  });

  it.each`
    scenario                                                                           | steps                                                                                                                       | lockedNote                                                                                                                                              | stateLine                          | progressLabel                      | status       | doneCount
    ${'flows locked off by the root group'}                                            | ${{ flowsOn: false, flowsLocked: true, ...LOCKED_BY_GROUP }}                                                                | ${'Flows are turned off by my-group.'}                                                                                                                  | ${'Agents work now.'}              | ${'Limited by my-group'}           | ${'limited'} | ${3}
    ${'flows locked off, agents off'}                                                  | ${{ agentsOn: false, flowsOn: false, flowsLocked: true, ...LOCKED_BY_GROUP }}                                               | ${'Flows are turned off by my-group.'}                                                                                                                  | ${'1 more step to set up agents.'} | ${'1 step left'}                   | ${'partial'} | ${2}
    ${'GitLab Duo locked off'}                                                         | ${{ duoOn: false, duoLocked: true, ...LOCKED_BY_GROUP }}                                                                    | ${'GitLab Duo is turned off by my-group. Settings you change here take effect when GitLab Duo is turned on.'}                                           | ${''}                              | ${'Limited by my-group'}           | ${'limited'} | ${3}
    ${'GitLab Duo locked off, flows off'}                                              | ${{ duoOn: false, duoLocked: true, flowsOn: false, ...LOCKED_BY_GROUP }}                                                    | ${'GitLab Duo is turned off by my-group. Settings you change here take effect when GitLab Duo is turned on.'}                                           | ${''}                              | ${'1 step left'}                   | ${'partial'} | ${2}
    ${'GitLab Duo and flows locked off'}                                               | ${{ duoOn: false, duoLocked: true, flowsOn: false, flowsLocked: true, ...LOCKED_BY_GROUP }}                                 | ${'GitLab Duo and flows are turned off by my-group. Settings you change here take effect when GitLab Duo is turned on.'}                                | ${''}                              | ${'Limited by my-group'}           | ${'limited'} | ${2}
    ${'flows locked off by an administrator'}                                          | ${{ flowsOn: false, flowsLocked: true, isSaaS: false }}                                                                     | ${'Flows are turned off by an administrator.'}                                                                                                          | ${'Agents work now.'}              | ${'Limited by your administrator'} | ${'limited'} | ${3}
    ${'GitLab Duo locked off by an administrator'}                                     | ${{ duoOn: false, duoLocked: true, isSaaS: false }}                                                                         | ${'GitLab Duo is turned off by an administrator. Settings you change here take effect when GitLab Duo is turned on.'}                                   | ${''}                              | ${'Limited by your administrator'} | ${'limited'} | ${3}
    ${'GitLab Duo locked off by the root group, flows locked off by an administrator'} | ${{ duoOn: false, duoLocked: true, duoLockedBy: 'my-group', flowsOn: false, flowsLocked: true }}                            | ${'GitLab Duo is turned off by my-group. Flows are turned off by an administrator. Settings you change here take effect when GitLab Duo is turned on.'} | ${''}                              | ${'Limited by my-group'}           | ${'limited'} | ${2}
    ${'GitLab Duo locked off by an administrator, flows locked off by the root group'} | ${{ duoOn: false, duoLocked: true, flowsOn: false, flowsLocked: true, flowsLockedBy: 'my-group', isSaaS: false }}           | ${'GitLab Duo is turned off by an administrator. Flows are turned off by my-group. Settings you change here take effect when GitLab Duo is turned on.'} | ${''}                              | ${'Limited by your administrator'} | ${'limited'} | ${2}
    ${'GitLab Duo and flows locked off by different groups'}                           | ${{ duoOn: false, duoLocked: true, duoLockedBy: 'parent-a', flowsOn: false, flowsLocked: true, flowsLockedBy: 'parent-b' }} | ${'GitLab Duo is turned off by parent-a. Flows are turned off by parent-b. Settings you change here take effect when GitLab Duo is turned on.'}         | ${''}                              | ${'Limited by parent-a'}           | ${'limited'} | ${2}
    ${'flows locked off by an administrator while the root group locks GitLab Duo on'} | ${{ duoLocked: true, duoLockedBy: 'my-group', flowsOn: false, flowsLocked: true }}                                          | ${'Flows are turned off by an administrator.'}                                                                                                          | ${'Agents work now.'}              | ${'Limited by your administrator'} | ${'limited'} | ${3}
  `(
    'leaves $scenario out of the steps left',
    ({ steps, lockedNote, stateLine, progressLabel, status, doneCount }) => {
      expect(readinessSummary({ ...ALL_ON, ...steps })).toMatchObject({
        lockedNote,
        stateLine,
        progressLabel,
        status,
        doneCount,
      });
    },
  );

  it('ignores a lock on a step that is on', () => {
    expect(
      readinessSummary({ ...ALL_ON, duoLocked: true, flowsLocked: true, ...LOCKED_BY_GROUP }),
    ).toMatchObject({
      lockedNote: '',
      stateLine: 'Agents and flows are ready in this group.',
      progressLabel: 'Setup complete',
      status: 'complete',
    });
  });
});

describe('lockingGroup', () => {
  it.each`
    cascadingSettings                                                        | group
    ${null}                                                                  | ${null}
    ${{ lockedByAncestor: false, lockedByApplicationSetting: true }}         | ${null}
    ${{ lockedByAncestor: true, ancestorNamespace: { fullName: 'parent' } }} | ${'parent'}
    ${{ lockedByAncestor: true, ancestorNamespace: null }}                   | ${'root'}
  `('returns $group for $cascadingSettings', ({ cascadingSettings, group }) => {
    expect(lockingGroup(cascadingSettings, 'root')).toBe(group);
  });
});

describe('isLocked', () => {
  it.each`
    cascadingSettings                                                 | locked
    ${null}                                                           | ${false}
    ${{ lockedByAncestor: false, lockedByApplicationSetting: false }} | ${false}
    ${{ lockedByAncestor: true, lockedByApplicationSetting: false }}  | ${true}
    ${{ lockedByAncestor: false, lockedByApplicationSetting: true }}  | ${true}
  `('returns $locked for $cascadingSettings', ({ cascadingSettings, locked }) => {
    expect(isLocked(cascadingSettings)).toBe(locked);
  });
});

describe('stepStatus', () => {
  it('maps a done step to done and anything else to todo', () => {
    expect(stepStatus(true)).toBe('done');
    expect(stepStatus(false)).toBe('todo');
  });
});
