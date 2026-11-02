import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsManagerTrialAlert from 'ee/ci/secrets/components/secrets_manager_trial_alert.vue';
import {
  BLOCKED_REASON_CREDITS_EXHAUSTED,
  BLOCKED_REASON_GRACE,
  BLOCKED_REASON_ON_DEMAND_DISABLED,
  BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED,
  BLOCKED_REASON_TRIAL_EXPIRED,
} from 'ee/ci/secrets/constants';

const CREDITS_DOCS_HREF = '/help/ci/secrets/secrets_manager/credit_usage';
const SUBSCRIPTIONS_URL = 'https://customers.example.com';

describe('SecretsManagerTrialAlert', () => {
  let wrapper;

  const expiryFiveDays = new Date(Date.now() + 5 * 86400000).toISOString();
  const expiryOneDay = new Date(Date.now() + 86400000).toISOString();

  const createComponent = (
    entitlement = {},
    { writeDenialReason = null, isOfflineLicense = false } = {},
  ) => {
    wrapper = shallowMountExtended(SecretsManagerTrialAlert, {
      propsData: {
        writeDenialReason,
        entitlement: entitlement && {
          state: 'TRIAL',
          blockedReason: null,
          trialExpiresAt: expiryFiveDays,
          creditsRemaining: 500,
          creditsTotal: 500,
          onDemandEnabled: true,
          ...entitlement,
        },
      },
      provide: { isOfflineLicense, subscriptionsUrl: SUBSCRIPTIONS_URL },
      stubs: { GlSprintf },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findLink = () => wrapper.findComponent(GlLink);

  it.each(['TRIAL_ELIGIBLE', 'PAID', 'OFFLINE_PAID', 'INELIGIBLE'])(
    'renders nothing in the %s state',
    (state) => {
      createComponent({ state });

      expect(findAlert().exists()).toBe(false);
    },
  );

  describe('during the trial', () => {
    it('shows credits left and days remaining from day one as a warning', () => {
      createComponent();

      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().props('title')).toBe(
        '100% of GitLab Secrets Manager trial credits left. If not used up, they expire in 5 days.',
      );
    });

    it('pluralizes a single day', () => {
      createComponent({ trialExpiresAt: expiryOneDay });

      expect(findAlert().props('title')).toBe(
        '100% of GitLab Secrets Manager trial credits left. If not used up, they expire in 1 day.',
      );
    });

    it('says the credits expire today on the last calendar day', () => {
      createComponent({ trialExpiresAt: new Date().toISOString() });

      expect(findAlert().props('title')).toBe(
        '100% of GitLab Secrets Manager trial credits left. If not used up, they expire today.',
      );
    });

    it('omits the expiry when the trial has no end date', () => {
      createComponent({ trialExpiresAt: null, creditsRemaining: 250 });

      expect(findAlert().props('title')).toBe('50% of GitLab Secrets Manager trial credits left.');
    });

    it('explains on-demand billing with a credits docs link', () => {
      createComponent();

      expect(findAlert().text()).toContain(
        'When all trial credits are used up, GitLab Secrets Manager starts using GitLab Credits.',
      );
      expect(findLink().text()).toBe('How does GitLab Secrets Manager use GitLab Credits?');
      expect(findLink().attributes('href')).toBe(CREDITS_DOCS_HREF);
    });

    it('asks to contact the subscription owner when on-demand billing is off', () => {
      createComponent({ onDemandEnabled: false });

      expect(findAlert().text()).toContain(
        'Contact your subscription owner to purchase a Monthly Commitment of GitLab Credits or accept on-demand billing and avoid a service disruption.',
      );
      expect(findLink().attributes('href')).toBe(CREDITS_DOCS_HREF);
    });

    describe('when less than 10% of credits are left', () => {
      it('switches to a danger alert without the exact percentage', () => {
        createComponent({ creditsRemaining: 49 });

        expect(findAlert().props('variant')).toBe('danger');
        expect(findAlert().props('title')).toBe(
          'Less than 10% of GitLab Secrets Manager trial credits left. If not used up, they expire in 5 days.',
        );
      });

      it('says the credits expire today on the last calendar day', () => {
        createComponent({ creditsRemaining: 49, trialExpiresAt: new Date().toISOString() });

        expect(findAlert().props('title')).toBe(
          'Less than 10% of GitLab Secrets Manager trial credits left. If not used up, they expire today.',
        );
      });

      it('stays a warning at exactly 10%', () => {
        createComponent({ creditsRemaining: 50 });

        expect(findAlert().props('variant')).toBe('warning');
      });

      it('renders nothing once trial credits are used up and on-demand billing is on', () => {
        createComponent({ creditsRemaining: 0, onDemandEnabled: true });

        expect(findAlert().exists()).toBe(false);
      });
    });
  });

  describe('when blocked', () => {
    it.each([BLOCKED_REASON_TRIAL_EXPIRED, BLOCKED_REASON_CREDITS_EXHAUSTED])(
      'tells the user Secrets Manager is disabled with a Customer Portal link for %s',
      (blockedReason) => {
        createComponent({ state: 'BLOCKED', blockedReason });

        expect(findAlert().props('variant')).toBe('danger');
        expect(findAlert().props('title')).toBe('GitLab Secrets Manager is disabled');
        expect(findAlert().text()).toContain(
          'You can only view details or delete existing secrets.',
        );
        expect(findAlert().text()).toContain(
          'Please visit the Customer Portal or contact your subscription owner to purchase a Monthly Commitment of GitLab Credits',
        );
        expect(findLink().text()).toBe('Customer Portal');
        expect(findLink().attributes('href')).toBe(SUBSCRIPTIONS_URL);
      },
    );

    it.each`
      blockedReason                                       | title
      ${BLOCKED_REASON_GRACE}                             | ${'Your secrets manager subscription has been cancelled'}
      ${BLOCKED_REASON_ON_DEMAND_DISABLED}                | ${'On-demand billing is disabled'}
      ${BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED} | ${'Your secrets manager add-on has been removed from your license'}
    `('keeps the $blockedReason copy', ({ blockedReason, title }) => {
      createComponent({ state: 'BLOCKED', blockedReason });

      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().props('title')).toBe(title);
    });
  });

  describe('with a write denial reason', () => {
    it('shows the blocked copy without an entitlement', () => {
      createComponent(null, { writeDenialReason: 'TRIAL_EXPIRED' });

      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().props('title')).toBe('GitLab Secrets Manager is disabled');
    });

    it.each`
      isOfflineLicense | description
      ${true}          | ${'Contact your subscription owner to update your license so it includes GitLab Secrets Manager.'}
      ${false}         | ${'Contact your subscription owner to enable on-demand billing and avoid disruption.'}
    `(
      'shows the matching copy when the add-on is missing and isOfflineLicense is $isOfflineLicense',
      ({ isOfflineLicense, description }) => {
        createComponent(null, {
          writeDenialReason: BLOCKED_REASON_SUBSCRIPTION_GRACE_PERIOD_EXPIRED,
          isOfflineLicense,
        });

        expect(findAlert().text()).toBe(description);
      },
    );

    it('shows the blocked copy instead of the trial progress', () => {
      createComponent({ state: 'TRIAL' }, { writeDenialReason: 'ON_DEMAND_DISABLED' });

      expect(findAlert().props('title')).toBe('On-demand billing is disabled');
    });

    it('asks to contact an Owner or administrator when a trial is required', () => {
      createComponent(null, { writeDenialReason: 'TRIAL_REQUIRED' });

      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().text()).toBe(
        'Secrets are read-only until GitLab Secrets Manager is enabled. Contact your group owner or instance administrator to start a trial or enable with GitLab Credits.',
      );
    });

    it('renders nothing when a trial is required and the entitlement is readable', () => {
      createComponent({ state: 'TRIAL_ELIGIBLE' }, { writeDenialReason: 'TRIAL_REQUIRED' });

      expect(findAlert().exists()).toBe(false);
    });

    it('renders nothing for a reason without copy', () => {
      createComponent(null, { writeDenialReason: 'INELIGIBLE' });

      expect(findAlert().exists()).toBe(false);
    });
  });

  it('renders nothing without an entitlement or a write denial reason', () => {
    createComponent(null);

    expect(findAlert().exists()).toBe(false);
  });
});
