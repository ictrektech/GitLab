import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';

describe('OrbitTurnOnConfirmModal', () => {
  let wrapper;

  const offer = { durationDays: 30, initialCredits: 100 };
  const trialGroup = (name, groupOffer = offer) => ({
    fullPath: name,
    name,
    startsTrial: true,
    offer: groupOffer,
  });

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(TurnOnConfirmModal, {
      propsData: {
        visible: true,
        groups: [trialGroup('acme-platform')],
        loading: false,
        ...props,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findTrialText = () => wrapper.findByTestId('turn-on-trial-text');
  const findGroupList = () => wrapper.findByTestId('turn-on-group-list');

  describe('for one group that starts a trial', () => {
    beforeEach(() => createComponent());

    it('names the group in the title', () => {
      expect(findModal().props('title')).toBe('Turn on GitLab Orbit for acme-platform?');
    });

    it('shows the offer for the group', () => {
      expect(findTrialText().text()).toMatchInterpolatedText(
        'The group gets 100 credits for GitLab Orbit, valid for 30 days. When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
      );
    });

    it('lists no groups', () => {
      expect(findGroupList().exists()).toBe(false);
    });
  });

  describe('for several groups with different trials', () => {
    beforeEach(() =>
      createComponent({
        groups: [
          trialGroup('acme-platform'),
          trialGroup('data-eng', { durationDays: 14, initialCredits: 50 }),
          trialGroup('mobile-apps', null),
          { fullPath: 'payments', name: 'payments', startsTrial: false, offer: null },
        ],
      }),
    );

    it('counts the groups in the title', () => {
      expect(findModal().props('title')).toBe('Turn on GitLab Orbit for 4 groups?');
    });

    it('lists each group with its own trial and credits', () => {
      expect(
        findGroupList()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual([
        'acme-platform · 30-day trial, 100 credits',
        'data-eng · 14-day trial, 50 credits',
        'mobile-apps · Trial',
        'payments',
      ]);
    });

    it('says to contact sales after the trials', () => {
      expect(findTrialText().text()).toBe(
        'When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
      );
    });
  });

  describe('when CustomersDot sends no offer', () => {
    beforeEach(() => createComponent({ groups: [trialGroup('acme-platform', null)] }));

    it('mentions the trial and no offer numbers', () => {
      expect(findTrialText().text()).toContain('The group starts a GitLab Orbit trial.');
    });
  });

  describe('when no selected group starts a trial', () => {
    beforeEach(() =>
      createComponent({
        groups: [
          { fullPath: 'acme-platform', name: 'acme-platform', startsTrial: false, offer: null },
        ],
      }),
    );

    it('does not mention a trial', () => {
      expect(findTrialText().exists()).toBe(false);
    });
  });

  describe('during the instance trial on GitLab Self-Managed', () => {
    const instanceGroup = (name) => ({ fullPath: name, name, startsTrial: false, offer: null });

    it('says the group uses the instance trial and shares its credits', () => {
      createComponent({
        groups: [instanceGroup('acme-platform')],
        instanceTrialEndsOn: '2026-11-13',
      });

      expect(findTrialText().text()).toMatchInterpolatedText(
        'The group uses the trial of this instance until Nov 13, 2026. All groups on this instance share its credits. When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
      );
    });

    it('says the groups use the instance trial and share its credits', () => {
      createComponent({
        groups: [instanceGroup('acme-platform'), instanceGroup('mobile-apps')],
        instanceTrialEndsOn: '2026-11-13',
      });

      expect(findTrialText().text()).toMatchInterpolatedText(
        'These groups use the trial of this instance until Nov 13, 2026. All groups on this instance share its credits. When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
      );
    });
  });

  describe('while the groups turn on', () => {
    beforeEach(() => createComponent({ loading: true }));

    it('shows the primary action as loading and disables Cancel', () => {
      expect(findModal().props('actionPrimary').attributes.loading).toBe(true);
      expect(findModal().props('actionCancel').attributes.disabled).toBe(true);
    });
  });

  describe('when the user confirms', () => {
    const event = { preventDefault: jest.fn() };

    beforeEach(() => {
      createComponent();
      findModal().vm.$emit('primary', event);
    });

    it('emits confirm and keeps the modal open', () => {
      expect(wrapper.emitted('confirm')).toHaveLength(1);
      expect(event.preventDefault).toHaveBeenCalled();
    });
  });

  describe('when the modal closes', () => {
    beforeEach(() => {
      createComponent();
      findModal().vm.$emit('hidden');
    });

    it('emits hide', () => {
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });
});
