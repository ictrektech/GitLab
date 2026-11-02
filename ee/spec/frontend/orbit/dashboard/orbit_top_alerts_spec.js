import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import OrbitTopAlerts from 'ee/orbit/dashboard/orbit_top_alerts.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import { buildOrbitGroup } from '../mock_data';

const PREFERENCES_PATH = '/-/profile/preferences';
const BODY =
  'You can use GitLab Orbit when indexing is done, which may take several minutes to hours. You can leave this page and check back later.';
const acme = buildOrbitGroup({ id: 2, name: 'acme', state: 'INDEXING' });
const demo = buildOrbitGroup({ id: 1, name: 'gl-demo', state: 'INDEXING' });
const ready = buildOrbitGroup({ id: 3, name: 'ready-group' });

describe('OrbitTopAlerts', () => {
  let wrapper;

  const createComponent = ({ props = {}, defaultGroupMissing = false } = {}) => {
    wrapper = shallowMountExtended(OrbitTopAlerts, {
      propsData: {
        enabledGroups: [buildOrbitGroup()],
        ...props,
      },
      provide: { defaultGroupMissing, preferencesPath: PREFERENCES_PATH },
      stubs: { GlAlert },
    });
  };

  const findAlert = (testid) => wrapper.findComponentByTestId(testid);
  const findAlertBody = (testid) => findAlert(testid).find('.gl-alert-body');
  const alertIds = () =>
    wrapper.findAllComponents(GlAlert).wrappers.map((alert) => alert.attributes('data-testid'));

  describe('when the only group with Orbit on is indexing', () => {
    beforeEach(() => createComponent({ props: { enabledGroups: [acme] } }));

    it('shows an info alert with the group name and no action', () => {
      expect(findAlert('orbit-indexing-alert').props()).toMatchObject({
        variant: 'info',
        title: 'Indexing acme',
        dismissible: false,
        primaryButtonText: '',
        secondaryButtonText: '',
      });
    });

    it('tells the user to come back later', () => {
      expect(findAlertBody('orbit-indexing-alert').text()).toBe(BODY);
    });
  });

  describe.each`
    scenario     | enabledGroups          | title
    ${'some of'} | ${[acme, demo, ready]} | ${'Indexing 2 of 3 groups'}
    ${'all of'}  | ${[acme, demo]}        | ${'Indexing 2 of 2 groups'}
  `('when $scenario several groups are indexing', ({ enabledGroups, title }) => {
    beforeEach(() => createComponent({ props: { enabledGroups } }));

    it('counts the groups that index', () => {
      expect(findAlert('orbit-indexing-alert').props('title')).toBe(title);
    });
  });

  describe('when no group indexes', () => {
    beforeEach(() => createComponent());

    it('shows no alert', () => {
      expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
    });
  });

  describe('when the default group is missing', () => {
    beforeEach(() => createComponent({ defaultGroupMissing: true }));

    it('links to the Preferences page', () => {
      expect(findAlert('orbit-no-default-alert').props()).toMatchObject({
        variant: 'warning',
        primaryButtonText: 'Go to preferences',
        primaryButtonLink: PREFERENCES_PATH,
      });
    });
  });

  describe('when the default group is not missing but several groups are on', () => {
    beforeEach(() =>
      createComponent({ props: { enabledGroups: [demo, acme] }, defaultGroupMissing: false }),
    );

    it('shows no no-default-group alert', () => {
      expect(findAlert('orbit-no-default-alert').exists()).toBe(false);
    });
  });

  describe('when the no default group alert and the indexing alert both apply', () => {
    beforeEach(() =>
      createComponent({
        props: { enabledGroups: [acme, ready] },
        defaultGroupMissing: true,
      }),
    );

    it('shows the no default group alert first', () => {
      expect(alertIds()).toEqual(['orbit-no-default-alert', 'orbit-indexing-alert']);
    });
  });

  describe('when a trial has ended and the other alerts apply', () => {
    beforeEach(() =>
      createComponent({
        props: { endedTrialNamespaceId: 24, enabledGroups: [acme, ready] },
        defaultGroupMissing: true,
      }),
    );

    it('shows all three alerts, the trial ended alert first', () => {
      expect(alertIds()).toEqual([
        'orbit-trial-ended-alert',
        'orbit-no-default-alert',
        'orbit-indexing-alert',
      ]);
    });

    it('shows the warning', () => {
      expect(findAlert('orbit-trial-ended-alert').props()).toMatchObject({
        variant: 'warning',
        title: 'Trials have ended for some groups',
        dismissible: false,
      });
    });

    it('tells the user to contact sales', () => {
      expect(findAlertBody('orbit-trial-ended-alert').text()).toBe(
        'GitLab Orbit queries are paused for groups whose trial ended. Contact sales to keep using GitLab Orbit.',
      );
    });

    it('offers the hand-raise Contact sales button', () => {
      expect(
        findAlert('orbit-trial-ended-alert').findComponent(ContactSalesButton).props(),
      ).toMatchObject({ glmContent: 'orbit-trial-ended', namespaceId: 24 });
    });
  });
});
