import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { refreshCurrentPage } from '~/lib/utils/url_utility';
import OverviewQueriesLocked from 'ee/orbit/dashboard/overview/overview_queries_locked.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';

jest.mock('~/lib/utils/url_utility');

const ADMIN_PATH = '/admin/orbit';
const TRIAL_TITLE = 'Explore the map with a trial or a purchase';
const PURCHASE_TITLE = 'Explore the map with a purchase';
const MEMBER_TRIAL_TITLE = 'Try GitLab Orbit on this instance';
const MEMBER_PURCHASE_TEXT =
  'GitLab Orbit indexes your groups and counts their items. To explore the map and run GitLab Orbit queries, this instance needs a purchase. Contact sales, or ask your administrator.';
const OUTAGE_TITLE = 'Trial status is not available right now';
const OUTAGE_TEXT =
  'GitLab Orbit indexes your groups and counts their items. GitLab Orbit could not check the trial status of this instance. Try again later.';

describe('OverviewQueriesLocked', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(OverviewQueriesLocked, {
      propsData: { ...props },
    });
  };

  const findTitle = () => wrapper.find('h2');
  const findText = () => wrapper.findByTestId('overview-queries-locked-text');
  const findTrialButton = () => wrapper.findByTestId('overview-queries-locked-trial');
  const findRetryButton = () => wrapper.findComponentByTestId('overview-queries-locked-retry');
  const findContactSales = () => wrapper.findComponent(ContactSalesButton);

  describe.each`
    viewer                                               | props                                                                 | title                 | text                                                                                                                                                                                | trial    | retry    | sales
    ${'an administrator who can start the trial'}        | ${{ accessState: 'TRIAL_ELIGIBLE', adminPath: ADMIN_PATH }}           | ${TRIAL_TITLE}        | ${'GitLab Orbit indexes your groups and counts their items. Start the trial of this instance to explore the map and run GitLab Orbit queries. All groups share the trial credits.'} | ${true}  | ${false} | ${true}
    ${'an administrator with no trial'}                  | ${{ accessState: 'UNLICENSED', adminPath: ADMIN_PATH }}               | ${PURCHASE_TITLE}     | ${'GitLab Orbit indexes your groups and counts their items. To explore the map and run GitLab Orbit queries, contact sales to buy GitLab Orbit for this instance.'}                 | ${false} | ${false} | ${true}
    ${'a member when the trial can start'}               | ${{ accessState: 'TRIAL_ELIGIBLE' }}                                  | ${MEMBER_TRIAL_TITLE} | ${'GitLab Orbit indexes your groups and counts their items. Ask your administrator to start the trial of this instance to explore the map and run GitLab Orbit queries.'}           | ${false} | ${false} | ${false}
    ${'a member when the instance cannot start a trial'} | ${{ accessState: 'TRIAL_NOT_ELIGIBLE' }}                              | ${PURCHASE_TITLE}     | ${MEMBER_PURCHASE_TEXT}                                                                                                                                                             | ${false} | ${false} | ${true}
    ${'a member after the instance trial'}               | ${{ accessState: 'TRIAL_ENDED' }}                                     | ${PURCHASE_TITLE}     | ${MEMBER_PURCHASE_TEXT}                                                                                                                                                             | ${false} | ${false} | ${true}
    ${'an administrator during a CustomersDot outage'}   | ${{ accessState: 'TRIAL_STATUS_UNAVAILABLE', adminPath: ADMIN_PATH }} | ${OUTAGE_TITLE}       | ${OUTAGE_TEXT}                                                                                                                                                                      | ${false} | ${true}  | ${true}
    ${'a member during a CustomersDot outage'}           | ${{ accessState: 'TRIAL_STATUS_UNAVAILABLE' }}                        | ${OUTAGE_TITLE}       | ${OUTAGE_TEXT}                                                                                                                                                                      | ${false} | ${true}  | ${true}
  `('for $viewer', ({ props, title, text, trial, retry, sales }) => {
    beforeEach(() => createComponent(props));

    it('says how the instance gets Orbit queries', () => {
      expect(findTitle().text()).toBe(title);
      expect(findText().text()).toBe(text);
    });

    it('offers the actions that the state allows', () => {
      expect(findTrialButton().exists()).toBe(trial);
      expect(findRetryButton().exists()).toBe(retry);
      expect(findContactSales().exists()).toBe(sales);
    });
  });

  describe('when the instance needs a purchase', () => {
    beforeEach(() => createComponent({ accessState: 'UNLICENSED', adminPath: ADMIN_PATH }));

    it('tracks Contact sales as an overview queries lead', () => {
      expect(findContactSales().props('glmContent')).toBe('orbit-overview-queries');
    });
  });

  describe('when the instance trial can start', () => {
    beforeEach(() => createComponent({ accessState: 'TRIAL_ELIGIBLE', adminPath: ADMIN_PATH }));

    it('links Start trial to the Admin area', () => {
      expect(findTrialButton().attributes('href')).toBe(ADMIN_PATH);
    });
  });

  describe('when CustomersDot does not answer', () => {
    beforeEach(() => createComponent({ accessState: 'TRIAL_STATUS_UNAVAILABLE' }));

    it('reloads the page on Try again', () => {
      expect(refreshCurrentPage).not.toHaveBeenCalled();

      findRetryButton().vm.$emit('click');

      expect(refreshCurrentPage).toHaveBeenCalledTimes(1);
    });
  });
});
