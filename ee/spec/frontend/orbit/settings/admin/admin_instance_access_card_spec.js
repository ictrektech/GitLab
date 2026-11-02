import { GlBadge, GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import AdminInstanceAccessCard from 'ee/orbit/settings/admin/admin_instance_access_card.vue';
import { instanceAccess } from './mock_data';

describe('AdminInstanceAccessCard', () => {
  let wrapper;

  const createComponent = ({
    access = instanceAccess('LICENSED', 'PLAN'),
    starting = false,
    confirmVisible = false,
  } = {}) => {
    wrapper = shallowMountExtended(AdminInstanceAccessCard, {
      propsData: { access, starting, confirmVisible },
    });
  };

  const findTitle = () => wrapper.findByTestId('orbit-instance-access-title');
  const findText = () => wrapper.findByTestId('orbit-instance-access-text');
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findStartTrial = () => wrapper.findComponentByTestId('orbit-instance-start-trial');
  const findContactSales = () => wrapper.findComponent(ContactSalesButton);
  const findModal = () => wrapper.findComponent(GlModal);

  describe.each`
    scenario              | access                                                                         | title                                     | badge             | text
    ${'beta'}             | ${instanceAccess('LICENSED', 'PLAN')}                                          | ${'GitLab Orbit beta'}                    | ${'Beta'}         | ${'This instance is in the GitLab Orbit beta.'}
    ${'purchased'}        | ${instanceAccess('LICENSED', 'PROMO_ADD_ON')}                                  | ${'GitLab Orbit is on your subscription'} | ${'Purchased'}    | ${'You and the Owners of top-level groups can turn on GitLab Orbit.'}
    ${'trial with offer'} | ${instanceAccess('TRIAL_ELIGIBLE')}                                            | ${'Try GitLab Orbit on this instance'}    | ${'Trial'}        | ${'Start a trial to get 1,000 credits for GitLab Orbit queries, valid for 30 days. All groups share the credits.'}
    ${'trial, no offer'}  | ${instanceAccess('TRIAL_ELIGIBLE', null, { offer: null })}                     | ${'Try GitLab Orbit on this instance'}    | ${'Trial'}        | ${'You can turn on GitLab Orbit for groups now, and GitLab Orbit indexes them. Start a trial to run GitLab Orbit queries.'}
    ${'trial active'}     | ${instanceAccess('TRIAL_ACTIVE', null, { expiresOn: '2026-11-13' })}           | ${'Trial for this instance'}              | ${'Trial active'} | ${'The trial ends on Nov 13, 2026.'}
    ${'trial ended'}      | ${instanceAccess('TRIAL_ENDED', 'TRIAL_EXPIRED', { expiresOn: '2026-10-01' })} | ${'The trial of this instance has ended'} | ${'Trial ended'}  | ${'The trial ended on Oct 1, 2026. GitLab Orbit keeps indexing your groups'}
  `('when the instance is $scenario', ({ access, title, badge, text }) => {
    beforeEach(() => {
      createComponent({ access });
    });

    it('shows the title, badge, and text', () => {
      expect(findTitle().text()).toBe(title);
      expect(findBadge().text()).toBe(badge);
      expect(findText().text()).toContain(text);
    });
  });

  describe.each`
    scenario           | access                                        | title                                                 | text
    ${'not eligible'}  | ${instanceAccess('TRIAL_NOT_ELIGIBLE')}       | ${'Buy GitLab Orbit to run queries on this instance'} | ${'You can turn on GitLab Orbit for groups, and GitLab Orbit indexes them.'}
    ${'not available'} | ${instanceAccess('UNLICENSED', 'NO_LICENSE')} | ${'Get GitLab Orbit for this instance'}               | ${'Contact sales to get GitLab Orbit for this instance.'}
  `('when the instance is $scenario', ({ access, title, text }) => {
    beforeEach(() => {
      createComponent({ access });
    });

    it('shows the title and text, with no badge', () => {
      expect(findTitle().text()).toBe(title);
      expect(findText().text()).toContain(text);
      expect(findBadge().exists()).toBe(false);
    });
  });

  describe('when the trial is active with no end date', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ACTIVE') });
    });

    it('shows the shared credits without a date', () => {
      expect(findText().text()).toBe('All groups share the credits for GitLab Orbit queries.');
    });
  });

  describe('when the trial credits are used up before the end date', () => {
    beforeEach(() => {
      createComponent({
        access: instanceAccess('TRIAL_ENDED', 'CREDITS_EXHAUSTED', { expiresOn: '2026-11-30' }),
      });
    });

    it('says the credits are used up, with no end date', () => {
      expect(findBadge().text()).toBe('Credits used up');
      expect(findText().text()).toBe(
        'The trial credits are used up. GitLab Orbit keeps indexing your groups. Contact sales to buy GitLab Orbit and run queries again.',
      );
    });
  });

  describe('when the trial ended with no end date', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ENDED', 'TRIAL_EXPIRED') });
    });

    it('asks to contact sales without a date', () => {
      expect(findText().text()).toBe(
        'GitLab Orbit keeps indexing your groups, and GitLab Orbit queries are paused. You can still turn on GitLab Orbit for groups. Contact sales to buy GitLab Orbit and run queries again.',
      );
    });
  });

  describe.each`
    scenario             | access                                                | startTrial | contactSales
    ${'beta'}            | ${instanceAccess('LICENSED', 'PLAN')}                 | ${false}   | ${false}
    ${'purchased'}       | ${instanceAccess('LICENSED', 'PROMO_ADD_ON')}         | ${false}   | ${false}
    ${'trial'}           | ${instanceAccess('TRIAL_ELIGIBLE')}                   | ${true}    | ${false}
    ${'trial active'}    | ${instanceAccess('TRIAL_ACTIVE')}                     | ${false}   | ${true}
    ${'trial ended'}     | ${instanceAccess('TRIAL_ENDED')}                      | ${false}   | ${true}
    ${'credits used up'} | ${instanceAccess('TRIAL_ENDED', 'CREDITS_EXHAUSTED')} | ${false}   | ${true}
    ${'not eligible'}    | ${instanceAccess('TRIAL_NOT_ELIGIBLE')}               | ${false}   | ${true}
    ${'not available'}   | ${instanceAccess('UNLICENSED', 'NO_LICENSE')}         | ${false}   | ${true}
  `('actions when the instance is $scenario', ({ access, startTrial, contactSales }) => {
    beforeEach(() => {
      createComponent({ access });
    });

    it('offers Start trial and Contact sales as the state needs', () => {
      expect(findStartTrial().exists()).toBe(startTrial);
      expect(findContactSales().exists()).toBe(contactSales);
    });
  });

  describe('when Contact sales shows', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ACTIVE') });
    });

    it('links to the sales page', () => {
      expect(findContactSales().props()).toMatchObject({ glmContent: 'orbit-admin' });
    });
  });

  describe('when the trial is available', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ELIGIBLE') });
    });

    it('keeps the confirm closed', () => {
      expect(findModal().props('visible')).toBe(false);
    });

    it('emits show-confirm on Start trial', () => {
      findStartTrial().vm.$emit('click');

      expect(wrapper.emitted('show-confirm')).toEqual([[]]);
    });

    describe('when the confirm closes', () => {
      beforeEach(() => {
        findModal().vm.$emit('hidden');
      });

      it('emits hide-confirm', () => {
        expect(wrapper.emitted('hide-confirm')).toEqual([[]]);
      });
    });
  });

  describe('when the confirm is visible', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ELIGIBLE'), confirmVisible: true });
    });

    it('asks to confirm with the offer', () => {
      expect(findModal().props('visible')).toBe(true);
      expect(findModal().text()).toContain(
        'This instance gets 1,000 credits for GitLab Orbit queries, valid for 30 days. All groups share the credits.',
      );
      expect(findModal().text()).toContain(
        'After the trial starts, GitLab Orbit queries work for every group that has GitLab Orbit on.',
      );
    });

    it('emits start-trial on confirm', () => {
      findModal().vm.$emit('primary', { preventDefault: jest.fn() });

      expect(wrapper.emitted('start-trial')).toEqual([[]]);
    });
  });

  describe('while the trial starts', () => {
    beforeEach(() => {
      createComponent({ access: instanceAccess('TRIAL_ELIGIBLE'), starting: true });
    });

    it('shows the button and the confirm as loading', () => {
      expect(findStartTrial().props('loading')).toBe(true);
      expect(findModal().props('actionPrimary').attributes.loading).toBe(true);
      expect(findModal().props('actionCancel').attributes.disabled).toBe(true);
    });
  });
});
