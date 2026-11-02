import { nextTick } from 'vue';
import MockAdapter from 'axios-mock-adapter';
import axios from '~/lib/utils/axios_utils';
import { getCookie, removeCookie } from '~/lib/utils/common_utils';
import { groupCalloutsPath } from '~/lib/utils/path_helpers/user';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import {
  DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE,
  DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
  DUO_PANEL_EVENT_CLICK_REQUEST_DUO,
} from 'ee/ai/constants';
import { REQUEST_STATE, PAINTED_DOOR_FEATURES } from 'ee/painted_door_request/utils';
import AccessDeniedEmptyState from 'ee/ai/duo_agentic_chat/components/access_denied_empty_state.vue';
import DuoWorkflowExamplesCard from 'ee/ai/duo_agentic_chat/components/duo_workflow_examples_card.vue';

const { bindInternalEventDocument } = useMockInternalEventsTracking();

describe('AccessDeniedEmptyState', () => {
  let wrapper;
  let mock;

  const GROUP_ID = 123;
  const COOKIE_KEY = `painted_door_${PAINTED_DOOR_FEATURES.DUO_PANEL}_${GROUP_ID}`;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AccessDeniedEmptyState, {
      propsData: props,
      attachTo: document.body,
    });
  };

  const findEmptyStateText = () => wrapper.findByTestId('empty-state-text');
  const findWorkflowExamplesCard = () => wrapper.findComponent(DuoWorkflowExamplesCard);
  const findRequestButton = () => wrapper.findComponentByTestId('request-duo-button');
  const findLiveRegion = () => wrapper.findByTestId('request-duo-live-region');

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
    removeCookie(COOKIE_KEY);
  });

  describe('when the CTA is not eligible (no requestGroupId)', () => {
    beforeEach(createComponent);

    it('renders the heading', () => {
      expect(wrapper.text()).toContain("Your group doesn't have GitLab Duo yet");
    });

    it('renders the description', () => {
      expect(findEmptyStateText().text()).toBe(
        'Ask a group Owner to start a trial or purchase GitLab Credits to enable GitLab Duo for everyone.',
      );
    });

    it('renders the workflow examples card', () => {
      expect(findWorkflowExamplesCard().exists()).toBe(true);
      expect(findWorkflowExamplesCard().props()).toMatchObject({
        requestState: null,
        requestGroupId: null,
      });
    });

    it('does not render the request button', () => {
      expect(findRequestButton().exists()).toBe(false);
    });

    it('does not render the live region', () => {
      expect(findLiveRegion().exists()).toBe(false);
    });

    it('tracks the `view_duo_agentic_not_available_empty_state` on mount', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(DUO_PANEL_EVENT_VIEW_NOT_AVAILABLE, {}, undefined);
    });

    it('does not track the request empty-state view event', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
        expect.anything(),
        expect.anything(),
      );
    });
  });

  describe('state 1: not requested', () => {
    beforeEach(() => createComponent({ requestGroupId: GROUP_ID, requested: false }));

    it('renders "Request GitLab Duo" with no icon or aria-disabled attribute', () => {
      const button = findRequestButton();

      expect(button.text()).toBe('Request GitLab Duo');
      expect(button.props('icon')).toBe('');
      expect(button.attributes('aria-disabled')).toBeUndefined();
    });

    it('renders an empty, but present, live region', () => {
      expect(findLiveRegion().exists()).toBe(true);
      expect(findLiveRegion().text()).toBe('');
    });

    it('passes the request state down to the examples card', () => {
      expect(findWorkflowExamplesCard().props()).toMatchObject({
        requestState: REQUEST_STATE.NOT_REQUESTED,
        requestGroupId: GROUP_ID,
      });
    });

    it('tracks the request empty-state view event with the not_requested label', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
        { label: REQUEST_STATE.NOT_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('state 2: requested this session', () => {
    beforeEach(() => {
      document.cookie = `${COOKIE_KEY}=1`;
      createComponent({ requestGroupId: GROUP_ID, requested: true });
    });

    it('renders "Interest recorded" with a check icon and aria-disabled="true"', () => {
      const button = findRequestButton();

      expect(button.text()).toBe('Interest recorded');
      expect(button.props('icon')).toBe('check');
      expect(button.attributes('aria-disabled')).toBe('true');
    });

    it('fills the live region with the supporting text', () => {
      expect(findLiveRegion().text()).toBe(
        "Thank you for your interest. Your group Owner isn't notified, so ask them directly if you need GitLab Credits.",
      );
    });

    it('tracks the request empty-state view event with the requested label', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
        { label: REQUEST_STATE.REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('state 3: previously requested (no session key)', () => {
    beforeEach(() => createComponent({ requestGroupId: GROUP_ID, requested: true }));

    it('does not render the request button', () => {
      expect(findRequestButton().exists()).toBe(false);
    });

    it('renders an empty, but present, live region', () => {
      expect(findLiveRegion().exists()).toBe(true);
      expect(findLiveRegion().text()).toBe('');
    });

    it('tracks the request empty-state view event with the previously_requested label', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        DUO_PANEL_EVENT_VIEW_REQUEST_EMPTY_STATE,
        { label: REQUEST_STATE.PREVIOUSLY_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('clicking the request button', () => {
    beforeEach(() => {
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_OK);
      createComponent({ requestGroupId: GROUP_ID, requested: false });
    });

    it('switches to the requested state immediately (optimistic UI)', async () => {
      findRequestButton().vm.$emit('click');
      await nextTick();

      expect(findRequestButton().text()).toBe('Interest recorded');
    });

    it('keeps the same button element across the state change, so focus is retained', async () => {
      // Full mount: a shallow-stubbed GlButton is not a real focusable element in jsdom.
      const fullWrapper = mountExtended(AccessDeniedEmptyState, {
        propsData: { requestGroupId: GROUP_ID, requested: false },
        attachTo: document.body,
      });
      const findButton = () => fullWrapper.findByTestId('request-duo-button');
      const buttonBeforeClick = findButton().element;
      buttonBeforeClick.focus();
      expect(document.activeElement).toBe(buttonBeforeClick);

      await findButton().trigger('click');

      expect(findButton().element).toBe(buttonBeforeClick);
      expect(document.activeElement).toBe(buttonBeforeClick);
    });

    it('writes the cookie once the POST succeeds', async () => {
      findRequestButton().vm.$emit('click');
      await waitForPromises();

      expect(getCookie(COOKIE_KEY)).toBe('1');
    });

    it('keeps showing "Interest recorded" when remounted with the page-load props', async () => {
      findRequestButton().vm.$emit('click');
      await waitForPromises();
      wrapper.destroy();

      createComponent({ requestGroupId: GROUP_ID, requested: false });

      expect(findRequestButton().text()).toBe('Interest recorded');
    });

    it('posts the callout payload', async () => {
      await findRequestButton().vm.$emit('click');
      await waitForPromises();

      expect(mock.history.post).toHaveLength(1);
      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        feature_name: PAINTED_DOOR_FEATURES.DUO_PANEL,
        group_id: GROUP_ID,
      });
    });

    it('fires the click event with the property only, and no label', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await findRequestButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        DUO_PANEL_EVENT_CLICK_REQUEST_DUO,
        { property: String(GROUP_ID) },
        undefined,
      );
    });

    it('fills the live region with the supporting text on click', async () => {
      findRequestButton().vm.$emit('click');
      await nextTick();

      expect(findLiveRegion().text()).toBe(
        "Thank you for your interest. Your group Owner isn't notified, so ask them directly if you need GitLab Credits.",
      );
    });

    it('does not fire a second click event or POST on a second click', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await findRequestButton().vm.$emit('click');
      await waitForPromises();
      trackEventSpy.mockClear();

      await findRequestButton().vm.$emit('click');
      await waitForPromises();

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        DUO_PANEL_EVENT_CLICK_REQUEST_DUO,
        expect.anything(),
        expect.anything(),
      );
      expect(mock.history.post).toHaveLength(1);
    });
  });

  describe('when the POST fails', () => {
    beforeEach(() => {
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      createComponent({ requestGroupId: GROUP_ID, requested: false });
    });

    it('stays in the requested state for this page load', async () => {
      await findRequestButton().vm.$emit('click');
      await waitForPromises();

      expect(findRequestButton().text()).toBe('Interest recorded');
    });
  });
});
