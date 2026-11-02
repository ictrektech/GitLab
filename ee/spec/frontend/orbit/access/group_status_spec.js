import { buildGroupStatusRow } from 'ee/orbit/access/group_status';
import { useFakeDate } from 'helpers/fake_date';

const buildRow = (group, options = {}) => buildGroupStatusRow(group, { saas: true, ...options });

const OFFER = { durationDays: 30, initialCredits: 100 };

const buildGroup = ({
  readOrbitSetting = true,
  enabled = false,
  updateKnowledgeGraphSetting = true,
  startOrbitTrial = true,
  orbit = {},
  state = 'LICENSED',
  reason = 'PLAN',
  turnOnDenialReason = null,
  trial = null,
  access = { state, reason, turnOnDenialReason, trial },
} = {}) => ({
  id: 'gid://gitlab/Group/1',
  name: 'acme',
  fullPath: 'acme',
  webPath: '/acme',
  avatarUrl: null,
  userPermissions: { readOrbitSetting, startOrbitTrial, updateKnowledgeGraphSetting },
  orbit: { enabled, ...orbit, access },
});

const GROUP_CREDITS_PATH = '/groups/acme/-/settings/gitlab_credits_dashboard';
const ADMIN_CREDITS_PATH = '/admin/gitlab_credits_dashboard';

const eligibleGroup = (offer = OFFER) =>
  buildGroup({
    state: 'TRIAL_ELIGIBLE',
    reason: null,
    turnOnDenialReason: 'TRIAL_REQUIRED',
    trial: { state: 'ELIGIBLE', expiresOn: null, offer },
  });

const activeTrial = { state: 'ACTIVE', expiresOn: '2026-11-10', offer: null };

const onOrbit = (state, enabledAt = '2026-10-01T10:00:00Z') => ({
  enabledAt,
  indexing: state ? { state, areas: [{ name: 'core', state }] } : null,
});

describe('buildGroupStatusRow', () => {
  useFakeDate(2026, 9, 11, 12);

  describe('for an Owner or an administrator', () => {
    it('lets the Owner start a trial of a group that is off and eligible, and shows the offer', () => {
      const row = buildRow(eligibleGroup());

      expect(row).toMatchObject({
        allowedActions: ['turnOn'],
        isOn: false,
        startsTrial: true,
        turnOnAction: 'start_trial',
        offer: OFFER,
        trialBadge: { text: '100 credits when turned on', variant: 'info', icon: null },
        note: null,
        showsSales: false,
        creditsDashboardPath: null,
      });
    });

    it('exposes the numeric group id for Contact sales leads', () => {
      expect(buildRow(eligibleGroup()).namespaceId).toBe(1);
    });

    describe('when CustomersDot sends no offer', () => {
      it('shows a trial with no numbers', () => {
        expect(buildRow(eligibleGroup(null)).trialBadge.text).toBe('Trial when turned on');
      });
    });

    it('lets the Owner turn off a group that is on, and links to its GitLab Credits dashboard', () => {
      const row = buildRow(buildGroup({ enabled: true, orbit: onOrbit('READY') }));

      expect(row).toMatchObject({
        allowedActions: ['turnOff'],
        isOn: true,
        indexingState: 'READY',
        indexingAreas: [{ name: 'core', state: 'READY' }],
        enabledAt: '2026-10-01T10:00:00Z',
        creditsDashboardPath: GROUP_CREDITS_PATH,
      });
    });

    it.each`
      description                          | state             | reason                 | trial                                                       | badge                | note
      ${'an active trial'}                 | ${'TRIAL_ACTIVE'} | ${null}                | ${activeTrial}                                              | ${'Trial active'}    | ${'The trial ends on Nov 10, 2026.'}
      ${'a trial that ran out of credits'} | ${'TRIAL_ENDED'}  | ${'CREDITS_EXHAUSTED'} | ${{ state: 'ENDED', expiresOn: '2026-11-10', offer: null }} | ${'Credits used up'} | ${'This group has no GitLab Credits left. GitLab Orbit queries are paused until the group has GitLab Credits again.'}
      ${'a trial that expired'}            | ${'TRIAL_ENDED'}  | ${'TRIAL_EXPIRED'}     | ${{ state: 'ENDED', expiresOn: '2026-10-10', offer: null }} | ${'Trial ended'}     | ${'The trial ended on Oct 10, 2026. GitLab Orbit queries are paused.'}
    `('shows the trial of $description', ({ state, reason, trial, badge, note }) => {
      const row = buildRow(
        buildGroup({ enabled: true, orbit: onOrbit('READY'), state, reason, trial }),
      );

      expect(row.trialBadge.text).toBe(badge);
      expect(row.note).toBe(note);
    });

    it('exposes the end date of an active trial', () => {
      const row = buildRow(buildGroup({ state: 'TRIAL_ACTIVE', trial: activeTrial }));

      expect(row.trialEndsOn).toBe('2026-11-10');
    });

    it('offers sales for a group whose trial ended', () => {
      const row = buildRow(
        buildGroup({
          state: 'TRIAL_ENDED',
          reason: 'TRIAL_EXPIRED',
          turnOnDenialReason: 'TRIAL_ENDED',
          trial: { state: 'ENDED', expiresOn: '2026-10-01', offer: null },
        }),
      );

      expect(row).toMatchObject({
        allowedActions: [],
        turnOnAction: 'trial_ended',
        trialEndsOn: null,
        trialBadge: { text: 'Trial ended', variant: 'warning', icon: 'status-alert' },
        note: 'The trial ended on Oct 1, 2026. GitLab Orbit queries are paused.',
        showsSales: true,
        creditsDashboardPath: null,
      });
    });

    describe('when only the denial says the trial ended', () => {
      it('offers sales with no trial badge', () => {
        const row = buildRow(
          buildGroup({ state: 'LICENSED', reason: 'PLAN', turnOnDenialReason: 'TRIAL_ENDED' }),
        );

        expect(row).toMatchObject({
          turnOnAction: 'trial_ended',
          trialBadge: null,
          showsSales: true,
        });
      });
    });

    it('links to the GitLab Credits dashboard of a group that is on and not eligible for a trial', () => {
      const row = buildRow(
        buildGroup({
          enabled: true,
          orbit: onOrbit('READY'),
          state: 'TRIAL_NOT_ELIGIBLE',
          reason: null,
          trial: { state: 'NOT_ELIGIBLE', expiresOn: null, offer: null },
        }),
      );

      expect(row).toMatchObject({
        allowedActions: ['turnOff'],
        showsSales: false,
        creditsDashboardPath: GROUP_CREDITS_PATH,
      });
    });

    it('shows no trial for a beta group that keeps an old trial in CustomersDot', () => {
      const row = buildRow(
        buildGroup({
          reason: 'BETA',
          startOrbitTrial: false,
          trial: { state: 'ENDED', expiresOn: '2026-10-02', offer: null },
        }),
      );

      expect(row).toMatchObject({
        allowedActions: ['turnOn'],
        startsTrial: false,
        trialBadge: null,
        note: null,
        showsSales: false,
      });
    });

    it.each`
      description                        | group                                                                                                 | note                                                           | showsSales
      ${'a group with no Orbit license'} | ${buildGroup({ state: 'UNLICENSED', reason: 'FREE_PLAN', turnOnDenialReason: 'FORBIDDEN' })}          | ${'GitLab Orbit is available on Premium and Ultimate.'}        | ${true}
      ${'a group that needs a purchase'} | ${buildGroup({ state: 'UNLICENSED', reason: 'NO_ACCESS', turnOnDenialReason: 'PURCHASE_REQUIRED' })}  | ${'Contact sales to get GitLab Orbit for this group.'}         | ${true}
      ${'a group that is not eligible'}  | ${buildGroup({ state: 'TRIAL_NOT_ELIGIBLE', reason: null, turnOnDenialReason: 'TRIAL_REQUIRED' })}    | ${'Contact sales to get GitLab Orbit for this group.'}         | ${true}
      ${'a trial that did not load'}     | ${buildGroup({ state: 'TRIAL_STATUS_UNAVAILABLE', reason: null, turnOnDenialReason: 'UNAVAILABLE' })} | ${'Trial status is not available right now. Try again later.'} | ${false}
    `('explains $description and offers no turn on', ({ group, note, showsSales }) => {
      expect(buildRow(group)).toMatchObject({ allowedActions: [], note, showsSales });
    });
  });

  describe('on GitLab Self-Managed', () => {
    it('says Orbit is not available on an instance with no Orbit license', () => {
      const group = buildGroup({
        state: 'UNLICENSED',
        reason: 'NO_LICENSE',
        turnOnDenialReason: 'FORBIDDEN',
      });

      expect(buildRow(group, { saas: false })).toMatchObject({
        allowedActions: [],
        note: 'Contact sales to get GitLab Orbit for this instance.',
        showsSales: false,
      });
    });

    it.each`
      description                                         | state                   | startOrbitTrial
      ${'an instance trial that only an admin can start'} | ${'TRIAL_ELIGIBLE'}     | ${false}
      ${'an instance that is not eligible for a trial'}   | ${'TRIAL_NOT_ELIGIBLE'} | ${true}
      ${'no trial and no purchase'}                       | ${'UNLICENSED'}         | ${true}
    `(
      'lets the Owner turn on the group without a trial for $description',
      ({ state, startOrbitTrial }) => {
        const group = buildGroup({ state, reason: null, startOrbitTrial });

        expect(buildRow(group, { saas: false })).toMatchObject({
          allowedActions: ['turnOn'],
          turnOnAction: 'turn_on',
          trialBadge: null,
          note: null,
          showsSales: false,
        });
      },
    );

    it('shows the end date of the instance trial', () => {
      const row = buildRow(buildGroup({ state: 'TRIAL_ACTIVE', trial: activeTrial }), {
        saas: false,
      });

      expect(row).toMatchObject({
        allowedActions: ['turnOn'],
        note: 'The trial of this instance ends on Nov 10, 2026.',
        trialEndsOn: '2026-11-10',
      });
    });

    it('leaves Contact sales to the page alert for a trial that ended', () => {
      const row = buildRow(
        buildGroup({
          state: 'TRIAL_ENDED',
          reason: 'TRIAL_EXPIRED',
          turnOnDenialReason: 'TRIAL_ENDED',
          trial: { state: 'ENDED', expiresOn: '2026-10-01', offer: null },
        }),
        { saas: false },
      );

      expect(row).toMatchObject({ turnOnAction: 'trial_ended', showsSales: false });
    });

    it('says the instance trial used all its credits', () => {
      const row = buildRow(
        buildGroup({
          state: 'TRIAL_ENDED',
          reason: 'CREDITS_EXHAUSTED',
          turnOnDenialReason: 'TRIAL_ENDED',
          trial: { state: 'ENDED', expiresOn: '2026-11-10', offer: null },
        }),
        { saas: false },
      );

      expect(row.note).toBe(
        'The trial of this instance used all its credits. GitLab Orbit queries are paused.',
      );
    });
  });

  describe('for a member who cannot open Settings > Orbit', () => {
    it('allows no action, shows no trial, and asks for an Owner of a group that is off', () => {
      const row = buildRow(
        buildGroup({ readOrbitSetting: false, updateKnowledgeGraphSetting: false, access: null }),
      );

      expect(row).toMatchObject({
        allowedActions: [],
        turnOnAction: null,
        trialBadge: null,
        note: 'Ask an Owner of acme to turn on GitLab Orbit.',
        showsSales: false,
        creditsDashboardPath: null,
      });
    });

    it('shows the state of a group that is on, with no note', () => {
      const row = buildRow(
        buildGroup({
          readOrbitSetting: false,
          enabled: true,
          updateKnowledgeGraphSetting: false,
          orbit: onOrbit('INDEXING'),
          access: null,
        }),
      );

      expect(row).toMatchObject({
        isOn: true,
        indexingState: 'INDEXING',
        note: null,
        allowedActions: [],
      });
    });
  });

  describe('for the GitLab Credits dashboard link of a group that is on', () => {
    const onGroup = (readOrbitSetting) =>
      buildGroup({ readOrbitSetting, enabled: true, orbit: onOrbit('READY'), trial: null });

    it.each`
      description                               | dotCom   | isSelfManagedAdmin | readOrbitSetting | path
      ${'an Owner on GitLab.com'}               | ${true}  | ${false}           | ${true}          | ${GROUP_CREDITS_PATH}
      ${'a member on GitLab.com'}               | ${true}  | ${false}           | ${false}         | ${null}
      ${'an administrator on self-managed'}     | ${false} | ${true}            | ${true}          | ${ADMIN_CREDITS_PATH}
      ${'an Owner who is not an administrator'} | ${false} | ${false}           | ${true}          | ${null}
    `('is $path for $description', ({ dotCom, isSelfManagedAdmin, readOrbitSetting, path }) => {
      const row = buildRow(onGroup(readOrbitSetting), { saas: dotCom, isSelfManagedAdmin });

      expect(row.creditsDashboardPath).toBe(path);
    });
  });

  describe('for a subgroup', () => {
    const buildSubgroup = ({ enabled, indexing = null }) => ({
      ...buildGroup({ readOrbitSetting: false, updateKnowledgeGraphSetting: false }),
      name: 'web',
      fullPath: 'acme/web',
      webPath: '/acme/web',
      orbit: { enabled, enabledAt: null, indexing, access: null },
    });

    it('shows the index status of a subgroup of a group that is on, with no action', () => {
      const row = buildGroupStatusRow(
        buildSubgroup({ enabled: true, indexing: { state: 'READY', areas: [] } }),
      );

      expect(row).toMatchObject({
        isOn: true,
        indexingState: 'READY',
        allowedActions: [],
        trialBadge: null,
        note: null,
        creditsDashboardPath: null,
      });
    });

    it('asks for an Owner of the top-level group when Orbit is off', () => {
      const row = buildGroupStatusRow(buildSubgroup({ enabled: false }));

      expect(row).toMatchObject({
        isOn: false,
        allowedActions: [],
        note: 'Ask an Owner of the top-level group to turn on GitLab Orbit.',
      });
    });
  });

  describe('for the index status', () => {
    it.each`
      description                                        | orbit                                        | indexingState    | note
      ${'a failed index'}                                | ${onOrbit('FAILED')}                         | ${'FAILED'}      | ${'GitLab Orbit could not index this group. Contact support if this continues.'}
      ${'an unknown state'}                              | ${onOrbit('UNKNOWN')}                        | ${'UNKNOWN'}     | ${'GitLab Orbit has not reported a status for this group yet.'}
      ${'no status, turned on 5 minutes ago'}            | ${onOrbit(null, '2026-10-11T11:55:00.000Z')} | ${'NOT_STARTED'} | ${null}
      ${'no status, turned on more than 10 minutes ago'} | ${onOrbit(null, '2026-10-11T11:00:00.000Z')} | ${null}          | ${null}
    `('maps $description', ({ orbit, indexingState, note }) => {
      const row = buildRow(buildGroup({ enabled: true, orbit }));

      expect(row).toMatchObject({ indexingState, note });
    });
  });

  describe('for a group turned on at 11:50 with no status yet', () => {
    const group = buildGroup({ enabled: true, orbit: onOrbit(null, '2026-10-11T11:50:00.000Z') });

    it.each`
      now                                       | indexingState
      ${Date.parse('2026-10-11T11:55:00.000Z')} | ${'NOT_STARTED'}
      ${Date.parse('2026-10-11T12:05:00.000Z')} | ${null}
    `('shows the state $indexingState at $now', ({ now, indexingState }) => {
      expect(buildRow(group, { now }).indexingState).toBe(indexingState);
    });
  });

  it('shows the failure of the last action first', () => {
    const failure = { kind: 'rejected', message: 'Not allowed' };
    const row = buildRow(
      buildGroup({ state: 'TRIAL_NOT_ELIGIBLE', turnOnDenialReason: 'TRIAL_REQUIRED' }),
      { failure },
    );

    expect(row).toMatchObject({ failure, note: 'Not allowed' });
  });
});
