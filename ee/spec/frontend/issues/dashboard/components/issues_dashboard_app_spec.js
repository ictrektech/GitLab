import { shallowMount } from '@vue/test-utils';
import IssuesDashboardAppEE from 'ee/issues/dashboard/components/issues_dashboard_app.vue';
import IssuesDashboardApp from '~/issues/dashboard/components/issues_dashboard_app.vue';
import { TOKEN_TYPE_STATUS } from '~/vue_shared/components/filtered_search_bar/constants';

describe('IssuesDashboardAppEE component', () => {
  let wrapper;

  const findIssuesDashboardApp = () => wrapper.findComponent(IssuesDashboardApp);

  const mountComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMount(IssuesDashboardAppEE, {
      provide: {
        ...provide,
      },
    });
  };

  describe.each`
    flag         | licensed | available
    ${true}      | ${true}  | ${true}
    ${true}      | ${false} | ${false}
    ${false}     | ${true}  | ${false}
    ${false}     | ${false} | ${false}
    ${undefined} | ${true}  | ${false}
  `('when the flag is $flag and the license is $licensed', ({ flag, licensed, available }) => {
    beforeEach(() => {
      wrapper = shallowMount(IssuesDashboardAppEE, {
        provide: {
          hasStatusFeature: licensed,
          glFeatures: { workItemStatusOnDashboard: flag },
        },
        stubs: {
          IssuesDashboardApp: {
            inject: ['hasStatusSortFeature'],
            template: '<div>{{ hasStatusSortFeature }}</div>',
          },
        },
      });
    });

    it('provides status sorting availability to the dashboard', () => {
      expect(wrapper.text()).toBe(String(available));
    });
  });

  describe('tokens', () => {
    describe('when workItemStatusOnDashboard=true', () => {
      describe('when hasStatusFeature=true', () => {
        it('passes status token to IssuesDashboardApp', () => {
          mountComponent({
            provide: { hasStatusFeature: true, glFeatures: { workItemStatusOnDashboard: true } },
          });

          expect(findIssuesDashboardApp().props('eeSearchTokens')).toMatchObject([
            { type: TOKEN_TYPE_STATUS },
          ]);
        });
      });

      describe('when hasStatusFeature=false', () => {
        it('does not pass status token to IssuesDashboardApp', () => {
          mountComponent({
            provide: { hasStatusFeature: false, glFeatures: { workItemStatusOnDashboard: true } },
          });

          expect(findIssuesDashboardApp().props('eeSearchTokens')).toEqual([]);
        });
      });
    });

    describe('when workItemStatusOnDashboard=false', () => {
      describe('when hasStatusFeature=true', () => {
        it('does not pass status token to IssuesDashboardApp', () => {
          mountComponent({
            provide: { hasStatusFeature: true, glFeatures: { workItemStatusOnDashboard: false } },
          });

          expect(findIssuesDashboardApp().props('eeSearchTokens')).toEqual([]);
        });
      });

      describe('when hasStatusFeature=false', () => {
        it('does not pass status token to IssuesDashboardApp', () => {
          mountComponent({
            provide: { hasStatusFeature: false, glFeatures: { workItemStatusOnDashboard: false } },
          });

          expect(findIssuesDashboardApp().props('eeSearchTokens')).toEqual([]);
        });
      });
    });
  });
});
