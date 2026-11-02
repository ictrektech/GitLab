import {
  canTurnOn,
  deniedOnInstance,
  needsSales,
  startsTrial,
  trialEnded,
  trialInUse,
  turnOnAction,
} from 'ee/orbit/access/turn_on_action';

const TRIAL = { state: 'ACTIVE', expiresOn: '2026-11-13' };

const buildGroup = ({
  state = 'TRIAL_ELIGIBLE',
  reason = null,
  turnOnDenialReason = null,
  trial = TRIAL,
  startOrbitTrial = true,
  enabled = false,
  access = { state, reason, turnOnDenialReason, trial },
} = {}) => ({
  userPermissions: { startOrbitTrial },
  orbit: { enabled, access },
});

describe('turnOnAction', () => {
  it.each`
    description                                             | group                                                                                                | action
    ${'the user cannot read the access'}                    | ${buildGroup({ access: null })}                                                                      | ${'not_licensed'}
    ${'the server allows the turn on'}                      | ${buildGroup({ state: 'LICENSED', reason: 'PLAN' })}                                                 | ${'turn_on'}
    ${'the Owner can start the group trial'}                | ${buildGroup({ turnOnDenialReason: 'TRIAL_REQUIRED' })}                                              | ${'start_trial'}
    ${'only an administrator can start the instance trial'} | ${buildGroup({ turnOnDenialReason: 'TRIAL_REQUIRED', startOrbitTrial: false })}                      | ${'not_available'}
    ${'the group needs a purchase'}                         | ${buildGroup({ state: 'UNLICENSED', reason: 'NO_ACCESS', turnOnDenialReason: 'PURCHASE_REQUIRED' })} | ${'not_available'}
    ${'the user cannot change the setting'}                 | ${buildGroup({ state: 'UNLICENSED', reason: 'FREE_PLAN', turnOnDenialReason: 'FORBIDDEN' })}         | ${'not_licensed'}
    ${'the server reports an unknown denial'}               | ${buildGroup({ state: 'UNLICENSED', turnOnDenialReason: 'SOMETHING_NEW' })}                          | ${'not_available'}
    ${'the trial expired'}                                  | ${buildGroup({ state: 'TRIAL_ENDED', reason: 'TRIAL_EXPIRED', turnOnDenialReason: 'TRIAL_ENDED' })}  | ${'trial_ended'}
    ${'the trial used up its credits'}                      | ${buildGroup({ state: 'TRIAL_ENDED', reason: 'CREDITS_EXHAUSTED', enabled: true })}                  | ${'credits_used_up'}
    ${'the trial ended for a group that is on (no denial)'} | ${buildGroup({ state: 'TRIAL_ENDED', reason: 'TRIAL_EXPIRED', enabled: true })}                      | ${'trial_ended'}
    ${'the server denies with TRIAL_ENDED only'}            | ${buildGroup({ state: 'UNLICENSED', turnOnDenialReason: 'TRIAL_ENDED' })}                            | ${'trial_ended'}
    ${'the group is not eligible, despite TRIAL_REQUIRED'}  | ${buildGroup({ state: 'TRIAL_NOT_ELIGIBLE', turnOnDenialReason: 'TRIAL_REQUIRED' })}                 | ${'not_eligible'}
    ${'CustomersDot did not answer'}                        | ${buildGroup({ state: 'TRIAL_STATUS_UNAVAILABLE', turnOnDenialReason: 'UNAVAILABLE', trial: null })} | ${'unavailable'}
    ${'the server denies as unavailable'}                   | ${buildGroup({ state: 'UNLICENSED', turnOnDenialReason: 'UNAVAILABLE' })}                            | ${'unavailable'}
    ${'an instance without a trial indexes the group'}      | ${buildGroup({ state: 'TRIAL_NOT_ELIGIBLE' })}                                                       | ${'turn_on'}
    ${'a group that is on is not eligible for a trial'}     | ${buildGroup({ state: 'TRIAL_NOT_ELIGIBLE', enabled: true })}                                        | ${'not_eligible'}
  `('returns $action when $description', ({ group, action }) => {
    expect(turnOnAction(group)).toBe(action);
  });
});

describe('canTurnOn', () => {
  it.each`
    action               | expected
    ${'start_trial'}     | ${true}
    ${'turn_on'}         | ${true}
    ${'not_licensed'}    | ${false}
    ${'not_available'}   | ${false}
    ${'not_eligible'}    | ${false}
    ${'trial_ended'}     | ${false}
    ${'credits_used_up'} | ${false}
    ${'unavailable'}     | ${false}
  `('returns $expected for $action', ({ action, expected }) => {
    expect(canTurnOn(action)).toBe(expected);
  });
});

describe('startsTrial', () => {
  it.each`
    action           | expected
    ${'start_trial'} | ${true}
    ${'turn_on'}     | ${false}
  `('returns $expected for $action', ({ action, expected }) => {
    expect(startsTrial(action)).toBe(expected);
  });
});

describe('trialEnded', () => {
  it.each`
    action               | expected
    ${'trial_ended'}     | ${true}
    ${'credits_used_up'} | ${true}
    ${'not_available'}   | ${false}
    ${'turn_on'}         | ${false}
  `('returns $expected for $action', ({ action, expected }) => {
    expect(trialEnded(action)).toBe(expected);
  });
});

describe('deniedOnInstance', () => {
  it.each`
    action             | expected
    ${'not_licensed'}  | ${true}
    ${'not_available'} | ${true}
    ${'not_eligible'}  | ${true}
    ${'trial_ended'}   | ${false}
    ${'unavailable'}   | ${false}
    ${'turn_on'}       | ${false}
  `('returns $expected for $action', ({ action, expected }) => {
    expect(deniedOnInstance(action)).toBe(expected);
  });
});

describe('needsSales', () => {
  it.each`
    action               | expected
    ${'start_trial'}     | ${false}
    ${'turn_on'}         | ${false}
    ${'not_licensed'}    | ${true}
    ${'not_available'}   | ${true}
    ${'not_eligible'}    | ${true}
    ${'trial_ended'}     | ${true}
    ${'credits_used_up'} | ${true}
    ${'unavailable'}     | ${false}
  `('returns $expected for $action', ({ action, expected }) => {
    expect(needsSales(action)).toBe(expected);
  });

  describe('for a group that is on', () => {
    it.each`
      action               | expected
      ${'not_eligible'}    | ${false}
      ${'not_licensed'}    | ${true}
      ${'trial_ended'}     | ${true}
      ${'credits_used_up'} | ${true}
    `('returns $expected for $action', ({ action, expected }) => {
      expect(needsSales(action, { isOn: true })).toBe(expected);
    });
  });
});

describe('trialInUse', () => {
  it.each`
    state               | used
    ${'TRIAL_ACTIVE'}   | ${true}
    ${'TRIAL_ENDED'}    | ${true}
    ${'TRIAL_ELIGIBLE'} | ${false}
    ${'LICENSED'}       | ${false}
  `('returns the trial only while the access uses it ($state)', ({ state, used }) => {
    const group = buildGroup({ state });

    expect(trialInUse(group)).toBe(used ? group.orbit.access.trial : null);
  });

  describe('without access', () => {
    it('returns no trial', () => {
      expect(trialInUse(buildGroup({ access: null }))).toBe(null);
    });
  });
});
