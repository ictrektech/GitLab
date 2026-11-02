import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import ExploreAnalyticsDashboardDetailsEE from 'ee/explore/analytics_dashboards/pages/details.vue';
import waitForPromises from 'helpers/wait_for_promises';
import ExploreAnalyticsDashboardDetails from '~/explore/analytics_dashboards/pages/details.vue';
import AnalyzeWithDuoButton from 'ee/explore/analytics_dashboards/components/analyze_with_duo_button.vue';

describe('ExploreAnalyticsDashboardDetailsEE', () => {
  let wrapper;

  const createComponent = ({
    routeParams = { slug: '123' },
    isSystemDashboard = false,
    provide = {},
  } = {}) => {
    wrapper = shallowMountExtended(ExploreAnalyticsDashboardDetailsEE, {
      mocks: { $route: { params: routeParams } },
      provide,
      stubs: {
        AnalyzeWithDuoButton: stubComponent(AnalyzeWithDuoButton),
        // Render the CE component's #actions slot so the EE Edit button is mounted,
        // forwarding isSystemDashboard exactly as the CE component does.
        ExploreAnalyticsDashboardDetails: stubComponent(ExploreAnalyticsDashboardDetails, {
          template: `<div>
            <slot name="description-append"></slot>
            <slot name="actions" :is-system-dashboard="${isSystemDashboard}"></slot>
            <slot
              name="filter-actions"
              :filters="{ dateRangeOption: '30d', groups: ['dev-group'], projects: [] }"
              :panels="[{ title: 'Panel' }]"
              :duo-prompts="['Config prompt']"
              :is-system-dashboard="${isSystemDashboard}"
            ></slot>
          </div>`,
        }),
      },
    });
  };

  const findEditButton = () => wrapper.findComponentByTestId('dashboard-edit-button');
  const findCreditsDashboardLink = () =>
    wrapper.findComponentByTestId('gitlab-credits-dashboard-link');

  beforeEach(() => {
    createComponent();
  });

  it('renders the CE dashboard details component', () => {
    expect(wrapper.findComponent(ExploreAnalyticsDashboardDetails).exists()).toBe(true);
  });

  describe('edit button', () => {
    it('renders an Edit button with the pencil icon', () => {
      expect(findEditButton().exists()).toBe(true);
      expect(findEditButton().props('icon')).toBe('pencil');
      expect(findEditButton().text()).toBe('Edit');
    });

    it('links to the edit page for the current dashboard', () => {
      expect(findEditButton().props('to')).toEqual({
        name: 'dashboard-edit',
        params: { slug: '123' },
      });
    });
  });

  describe('GitLab Credits dashboard link', () => {
    const gitlabCreditsDashboardPath = '/admin/gitlab_credits_dashboard';

    it('links to the GitLab Credits dashboard in a new tab on DAP Impact', () => {
      createComponent({
        routeParams: { slug: 'dap_impact' },
        provide: { gitlabCreditsDashboardPath },
      });

      expect(findCreditsDashboardLink().attributes()).toMatchObject({
        href: gitlabCreditsDashboardPath,
        target: '_blank',
      });
      expect(findCreditsDashboardLink().text()).toBe('View GitLab Credits dashboard');
    });

    it('does not render on other dashboards', () => {
      createComponent({
        routeParams: { slug: 'duo_and_sdlc_trends' },
        provide: { gitlabCreditsDashboardPath },
      });

      expect(findCreditsDashboardLink().exists()).toBe(false);
    });

    it('does not render when the user has no GitLab Credits dashboard path', () => {
      createComponent({ routeParams: { slug: 'dap_impact' } });

      expect(findCreditsDashboardLink().exists()).toBe(false);
    });
  });

  describe('analyze with Duo button', () => {
    it('does not render on non-system dashboards', () => {
      expect(wrapper.findComponent(AnalyzeWithDuoButton).exists()).toBe(false);
    });

    describe('on a system dashboard', () => {
      beforeEach(async () => {
        createComponent({ isSystemDashboard: true });
        await waitForPromises();
      });

      it('renders in the filter actions slot with the dashboard context', () => {
        const button = wrapper.findComponent(AnalyzeWithDuoButton);

        expect(button.exists()).toBe(true);
        expect(button.props()).toMatchObject({
          filters: { dateRangeOption: '30d', groups: ['dev-group'], projects: [] },
          panels: [{ title: 'Panel' }],
          configPrompts: ['Config prompt'],
        });
      });
    });
  });

  describe('when viewing a system dashboard', () => {
    beforeEach(() => {
      createComponent({ isSystemDashboard: true });
    });

    it('does not render the Edit button', () => {
      expect(findEditButton().exists()).toBe(false);
    });
  });
});
