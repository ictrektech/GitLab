import { GlBadge, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserCalloutDismisser } from 'helpers/mock_user_callout_dismisser';
import IntroBanner from 'ee/explore/analytics_dashboards/components/intro_banner.vue';
import UserCalloutDismisser from '~/vue_shared/components/user_callout_dismisser.vue';

describe('IntroBanner', () => {
  let wrapper;
  let userCalloutDismissSpy;

  const createComponent = ({ shouldShowCallout = true } = {}) => {
    userCalloutDismissSpy = jest.fn();

    wrapper = shallowMountExtended(IntroBanner, {
      stubs: {
        UserCalloutDismisser: makeMockUserCalloutDismisser({
          dismiss: userCalloutDismissSpy,
          shouldShowCallout,
        }),
      },
    });
  };

  const findBanner = () => wrapper.findByTestId('intro-banner');
  const findDismissButton = () => wrapper.findComponentByTestId('dismiss-button');

  it('uses the analytics_dashboards_explore_intro_banner user callout', () => {
    createComponent();

    expect(wrapper.findComponent(UserCalloutDismisser).props('featureName')).toBe(
      'analytics_dashboards_explore_intro_banner',
    );
  });

  describe('when the callout has not been dismissed', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the banner content', () => {
      expect(findBanner().text()).toContain('Welcome to GitLab Intelligence');
      expect(findBanner().text()).toContain(
        'Organization-wide analytics with AI-assisted insights from GitLab Duo.',
      );
    });

    it('renders the "New" badge', () => {
      const badge = wrapper.findComponent(GlBadge);

      expect(badge.text()).toBe('New');
      expect(badge.props('variant')).toBe('info');
    });

    it('renders a "Learn more" link to the analytics dashboards docs', () => {
      const link = wrapper.findComponent(GlLink);

      expect(link.text()).toBe('Learn more');
      expect(link.attributes('href')).toBe('/help/user/analytics/analytics_dashboards');
    });

    it('renders an accessible dismiss button', () => {
      expect(findDismissButton().attributes('aria-label')).toBe('Dismiss');
    });

    it('dismisses the callout when the dismiss button is clicked', () => {
      findDismissButton().vm.$emit('click');

      expect(userCalloutDismissSpy).toHaveBeenCalled();
    });
  });

  describe('when the callout has been dismissed', () => {
    beforeEach(() => {
      createComponent({ shouldShowCallout: false });
    });

    it('does not render the banner', () => {
      expect(findBanner().exists()).toBe(false);
    });
  });
});
