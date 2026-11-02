import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  DUO_PANEL_EVENT_CLICK_VERIFY_ACCOUNT,
  DUO_PANEL_EVENT_VIEW_IDENTITY_VERIFICATION,
} from 'ee/ai/constants';
import IdentityVerificationEmptyState from 'ee/ai/duo_agentic_chat/components/identity_verification_empty_state.vue';

const { bindInternalEventDocument } = useMockInternalEventsTracking();

describe('IdentityVerificationEmptyState', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(IdentityVerificationEmptyState, {
      propsData: {
        identityVerificationPath: '/-/identity_verification',
        ...props,
      },
    });
  };

  const findEmptyStateText = () => wrapper.findByTestId('empty-state-text');
  const findVerifyAccountButton = () => wrapper.findByTestId('verify-account-link');

  beforeEach(createComponent);

  it('renders the correct content', () => {
    expect(findEmptyStateText().text()).toMatchInterpolatedText(
      'Before you can use GitLab Duo Agent Platform, we need to verify your account.',
    );

    expect(findVerifyAccountButton().text()).toBe('Verify my account');
    expect(findVerifyAccountButton().attributes('href')).toBe('/-/identity_verification');
  });

  it('tracks the `view_duo_agentic_identity_verification_empty_state` on mount', () => {
    const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

    expect(trackEventSpy).toHaveBeenCalledWith(
      DUO_PANEL_EVENT_VIEW_IDENTITY_VERIFICATION,
      {},
      undefined,
    );
  });

  it('tracks `click_duo_agentic_identity_verification_empty_state_verify_account` when clicked', () => {
    const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

    triggerEvent(findVerifyAccountButton().element);

    expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_CLICK_VERIFY_ACCOUNT, {});
  });
});
