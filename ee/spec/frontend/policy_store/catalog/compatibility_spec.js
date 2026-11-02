import {
  actionAllowedFor,
  actionTriggerBlockers,
  disabledActionReasons,
} from 'ee/policy_store/catalog/compatibility';
import { TRIGGER_KIND_EVENT, TRIGGER_KIND_GATE } from 'ee/policy_store/catalog/triggers';

describe('policy store trigger and action compatibility', () => {
  const gateTrigger = {
    id: 'project.before_settings_update',
    label: 'Project settings change requested',
    kind: TRIGGER_KIND_GATE,
  };
  const eventTrigger = {
    id: 'project.after_create',
    label: 'Project created',
    kind: TRIGGER_KIND_EVENT,
  };
  const blocking = { id: 'block', blocking: true };
  const nonBlocking = { id: 'log_audit_trail', blocking: false };
  // No `kind`/`blocking` key: what the editor synthesises for an id the local catalog
  // does not know.
  const unknownAction = { id: 'something_remote' };
  const unknownTrigger = { id: 'something_remote', label: 'something_remote' };
  // A kind the catalog does not know — the ADR's third kind, or a later revision adding a
  // fourth. Distinct from `unknownTrigger`, which declares no kind at all.
  const unknownKindTrigger = { id: 'scheduled_drift', label: 'Scheduled drift', kind: 'schedule' };

  describe('actionAllowedFor', () => {
    it.each`
      kind       | trigger         | action         | allowed
      ${'gate'}  | ${gateTrigger}  | ${blocking}    | ${true}
      ${'gate'}  | ${gateTrigger}  | ${nonBlocking} | ${true}
      ${'event'} | ${eventTrigger} | ${blocking}    | ${false}
      ${'event'} | ${eventTrigger} | ${nonBlocking} | ${true}
    `('a $kind trigger allows $action.id: $allowed', ({ trigger, action, allowed }) => {
      expect(actionAllowedFor(trigger, action)).toBe(allowed);
    });

    // GOVERN-016 rejects a blocking action on an event trigger and says nothing against the
    // reverse: recording a decision is as valid before the change as after it.
    it('rules out nothing but a blocking action on an event trigger', () => {
      expect(actionAllowedFor(gateTrigger, nonBlocking)).toBe(true);
      expect(actionAllowedFor(eventTrigger, blocking)).toBe(false);
    });

    it('allows everything while no trigger is selected', () => {
      expect(actionAllowedFor(undefined, blocking)).toBe(true);
      expect(actionAllowedFor(undefined, nonBlocking)).toBe(true);
    });

    // Hiding something the backend advertises behind a rule the frontend invented is the
    // worse failure, so an entry the local catalog does not know is allowed — and a
    // trigger with no kind must not be read as an event trigger, which would disable every
    // blocking action and claim a reason nobody knows to be true.
    it('allows an action that declares no blocking flag', () => {
      expect(actionAllowedFor(gateTrigger, unknownAction)).toBe(true);
      expect(actionAllowedFor(eventTrigger, unknownAction)).toBe(true);
    });

    it('allows every action under a trigger that declares no kind', () => {
      expect(actionAllowedFor(unknownTrigger, blocking)).toBe(true);
      expect(actionAllowedFor(unknownTrigger, nonBlocking)).toBe(true);
    });

    // Not `event` by elimination: a kind this catalog does not know must fail open like any
    // other unrecognised entry, rather than silently disabling every blocking action.
    it('allows every action under a trigger whose kind it does not know', () => {
      expect(actionAllowedFor(unknownKindTrigger, blocking)).toBe(true);
      expect(actionAllowedFor(unknownKindTrigger, nonBlocking)).toBe(true);
    });
  });

  describe('disabledActionReasons', () => {
    const actions = [blocking, nonBlocking, unknownAction];

    it('names only the actions the trigger cannot be answered with', () => {
      expect(Object.keys(disabledActionReasons(eventTrigger, actions))).toEqual(['block']);
    });

    it.each([
      ['no trigger is selected', undefined],
      ['the trigger is asked before the change', gateTrigger],
      ['the trigger declares no kind', unknownTrigger],
      ['the trigger declares a kind the catalog does not know', unknownKindTrigger],
    ])('disables nothing while %s', (_, trigger) => {
      expect(disabledActionReasons(trigger, actions)).toEqual({});
    });

    it('disables nothing when there are no actions', () => {
      expect(disabledActionReasons(eventTrigger)).toEqual({});
    });

    it('gives a reason that names the trigger and says which way it runs', () => {
      expect(disabledActionReasons(eventTrigger, actions).block).toBe(
        'Not available with Project created, which runs after the change: there is nothing left to stop.',
      );
    });
  });

  describe('actionTriggerBlockers', () => {
    const triggers = [gateTrigger, eventTrigger, unknownTrigger, unknownKindTrigger];
    const actions = [
      { ...blocking, label: 'Block' },
      { id: 'require_approval', blocking: true, label: 'Require approval' },
      { ...nonBlocking, label: 'Log to audit trail' },
      unknownAction,
    ];
    const blockersFor = (triggerId, actionIds) =>
      actionTriggerBlockers({ triggers, actions }, triggerId, actionIds);

    it('names every selected action the trigger cannot be answered with', () => {
      expect(blockersFor(eventTrigger.id, ['block', 'require_approval'])).toEqual([
        'Block is not available with Project created, which runs after the change: there is nothing left to stop.',
        'Require approval is not available with Project created, which runs after the change: there is nothing left to stop.',
      ]);
    });

    it('ignores actions that are allowed or not selected', () => {
      expect(blockersFor(eventTrigger.id, ['log_to_audit_trail', 'something_remote'])).toEqual([]);
    });

    it.each([
      ['no trigger is selected', null],
      ['the trigger is asked before the change', gateTrigger.id],
      ['the trigger declares no kind', 'something_remote'],
      ['the trigger declares a kind the catalog does not know', 'scheduled_drift'],
      ['the trigger is not in the catalog', 'invented_elsewhere'],
    ])('blocks nothing while %s', (_, triggerId) => {
      expect(blockersFor(triggerId, ['block', 'require_approval'])).toEqual([]);
    });

    it('blocks nothing when no actions are selected', () => {
      expect(actionTriggerBlockers({ triggers, actions }, eventTrigger.id)).toEqual([]);
    });
  });
});
