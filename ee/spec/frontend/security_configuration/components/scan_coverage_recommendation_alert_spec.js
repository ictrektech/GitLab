import { GlAlert, GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserGroupCalloutDismisser } from 'helpers/mock_user_group_callout_dismisser';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import ScanCoverageRecommendationAlert from 'ee/security_configuration/components/scan_coverage_recommendation_alert.vue';

describe('ScanCoverageRecommendationAlert', () => {
  let wrapper;
  let dismissSpy;

  const warningPayload = {
    variant: 'warning',
    title: 'No projects are scanned yet',
    message:
      'Apply the recommended scanner profile to all 125 projects to start finding vulnerabilities before they are merged.',
    ctaText: 'Enable scanners',
    ctaUrl: '/groups/tanuki-tech/-/security/inventory',
    bannerType: 'no_scanners',
  };

  const createComponent = ({
    scanCoverageBanner = warningPayload,
    shouldShowCallout = true,
  } = {}) => {
    dismissSpy = jest.fn();

    wrapper = shallowMountExtended(ScanCoverageRecommendationAlert, {
      provide: {
        groupId: 7,
        scanCoverageBanner,
      },
      stubs: {
        GlAlert,
        UserGroupCalloutDismisser: makeMockUserGroupCalloutDismisser({
          dismiss: dismissSpy,
          shouldShowCallout,
        }),
      },
    });
  };

  const findDismisser = () => wrapper.findComponent(UserGroupCalloutDismisser);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findButton = () => wrapper.findComponent(GlButton);

  describe('when there is no banner payload', () => {
    beforeEach(() => {
      createComponent({ scanCoverageBanner: null });
    });

    it('renders nothing', () => {
      expect(findDismisser().exists()).toBe(false);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when a warning payload is injected', () => {
    beforeEach(() => {
      createComponent();
    });

    it('passes the feature name and group id to the dismisser', () => {
      expect(findDismisser().props()).toMatchObject({
        featureName: 'scan_coverage_recommendation_banner',
        groupId: 7,
        skipQuery: true,
      });
    });

    it('renders a GlAlert with the correct variant, title, and message', () => {
      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().props('title')).toBe(warningPayload.title);
      expect(findAlert().text()).toContain(warningPayload.message);
    });

    it('renders a GlButton with the correct href and text', () => {
      expect(findButton().attributes('href')).toBe(warningPayload.ctaUrl);
      expect(findButton().text()).toBe(warningPayload.ctaText);
    });

    it('calls through to the dismisser dismiss function when the alert is dismissed', () => {
      findAlert().vm.$emit('dismiss');

      expect(dismissSpy).toHaveBeenCalled();
    });
  });

  describe('when the dismisser reports the callout should not be shown', () => {
    beforeEach(() => {
      createComponent({ shouldShowCallout: false });
    });

    it('keeps the dismisser mounted but hides the alert', () => {
      expect(findDismisser().exists()).toBe(true);
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when a tip payload is injected', () => {
    beforeEach(() => {
      createComponent({ scanCoverageBanner: { ...warningPayload, variant: 'tip' } });
    });

    it('renders a GlAlert with variant "tip"', () => {
      expect(findAlert().props('variant')).toBe('tip');
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks a view event with the banner type when the alert becomes visible', () => {
      const { trackEventSpy } = bindInternalEventDocument();
      createComponent();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_scan_coverage_recommendation_banner',
        { label: 'no_scanners' },
        undefined,
      );
    });

    it('does not track a view event when the callout should not be shown', () => {
      const { trackEventSpy } = bindInternalEventDocument();
      createComponent({ shouldShowCallout: false });

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('does not track a view event when there is no banner payload', () => {
      const { trackEventSpy } = bindInternalEventDocument();
      createComponent({ scanCoverageBanner: null });

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks a validated click event via the declarative CTA attributes', () => {
      createComponent();
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findButton().element);

      expect(trackEventSpy).toHaveBeenCalledWith('click_scan_coverage_recommendation_banner_cta', {
        label: 'no_scanners',
      });
    });

    it('renders the CTA with declarative click tracking attributes for the banner type', () => {
      createComponent();

      expect(findButton().attributes('data-event-tracking')).toBe(
        'click_scan_coverage_recommendation_banner_cta',
      );
      expect(findButton().attributes('data-event-label')).toBe('no_scanners');
    });

    it('tracks a dismiss event with the banner type before dismissing', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findAlert().vm.$emit('dismiss');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'dismiss_scan_coverage_recommendation_banner',
        { label: 'no_scanners' },
        undefined,
      );
      expect(dismissSpy).toHaveBeenCalled();
    });
  });
});
