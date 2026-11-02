import MockAdapter from 'axios-mock-adapter';
import axios from '~/lib/utils/axios_utils';
import { getCookie, removeCookie } from '~/lib/utils/common_utils';
import { groupCalloutsPath } from '~/lib/utils/path_helpers/user';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { REQUEST_STATE, PAINTED_DOOR_FEATURES } from 'ee/painted_door_request/utils';
import UserMenuExplorePremium from 'ee/super_sidebar/components/user_menu_explore_premium.vue';
import ExplorePremiumModal from 'ee/super_sidebar/components/explore_premium_modal.vue';

const { bindInternalEventDocument } = useMockInternalEventsTracking();

describe('UserMenuExplorePremium', () => {
  let wrapper;
  let mock;

  const GROUP_ID = 42;
  const COOKIE_KEY = `painted_door_${PAINTED_DOOR_FEATURES.EXPLORE_PREMIUM}_${GROUP_ID}`;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(UserMenuExplorePremium, {
      propsData: { groupId: GROUP_ID, ...props },
    });
  };

  const findItem = () => wrapper.findComponentByTestId('explore-premium-item');
  const findModal = () => wrapper.findComponent(ExplorePremiumModal);

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
    removeCookie(COOKIE_KEY);
  });

  it('renders the item with the "Explore Premium" text', () => {
    createComponent();

    expect(findItem().text()).toContain('Explore Premium');
  });

  it('does not show the modal initially', () => {
    createComponent();

    expect(findModal().props('visible')).toBe(false);
  });

  describe('state 1: not requested', () => {
    beforeEach(() => createComponent({ requested: false }));

    it('passes the not_requested state to the modal', () => {
      expect(findModal().props('state')).toBe(REQUEST_STATE.NOT_REQUESTED);
    });
  });

  describe('state 2: requested this session', () => {
    beforeEach(() => {
      document.cookie = `${COOKIE_KEY}=1`;
      createComponent({ requested: true });
    });

    it('passes the requested state to the modal', () => {
      expect(findModal().props('state')).toBe(REQUEST_STATE.REQUESTED);
    });
  });

  describe('state 3: previously requested (no cookie)', () => {
    beforeEach(() => createComponent({ requested: true }));

    it('passes the previously_requested state to the modal', () => {
      expect(findModal().props('state')).toBe(REQUEST_STATE.PREVIOUSLY_REQUESTED);
    });
  });

  describe('clicking the item', () => {
    beforeEach(() => createComponent({ requested: false }));

    it('opens the modal', async () => {
      await findItem().vm.$emit('action');

      expect(findModal().props('visible')).toBe(true);
    });

    it('emits action so the parent closes the dropdown', () => {
      findItem().vm.$emit('action');

      expect(wrapper.emitted('action')).toHaveLength(1);
    });

    it('tracks the click event with the state label and group id property', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findItem().vm.$emit('action');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_explore_premium_user_menu_item',
        { label: REQUEST_STATE.NOT_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('handleMenuShown (forwarded from the user menu dropdown @shown event)', () => {
    it('tracks the view event with the state label and group id property', () => {
      createComponent({ requested: false });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      wrapper.vm.handleMenuShown();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_explore_premium_user_menu_item',
        { label: REQUEST_STATE.NOT_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('requesting from the modal', () => {
    beforeEach(() => {
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_OK);
      createComponent({ requested: false });
      findItem().vm.$emit('action');
    });

    it('switches to the requested state immediately (optimistic UI)', async () => {
      findModal().vm.$emit('request');
      await waitForPromises();

      expect(findModal().props('state')).toBe(REQUEST_STATE.REQUESTED);
    });

    it('writes the cookie once the POST succeeds', async () => {
      findModal().vm.$emit('request');
      await waitForPromises();

      expect(getCookie(COOKIE_KEY)).toBe('1');
    });

    it('posts the callout payload', async () => {
      findModal().vm.$emit('request');
      await waitForPromises();

      expect(mock.history.post).toHaveLength(1);
      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        feature_name: PAINTED_DOOR_FEATURES.EXPLORE_PREMIUM,
        group_id: GROUP_ID,
      });
    });

    it('fires the request click event with the property only, and no label', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('request');
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_request_premium_features_explore_premium_modal',
        { property: String(GROUP_ID) },
        undefined,
      );
    });

    it('does not fire a second request event or POST on a second request', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('request');
      await waitForPromises();
      trackEventSpy.mockClear();

      findModal().vm.$emit('request');
      await waitForPromises();

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        'click_request_premium_features_explore_premium_modal',
        expect.anything(),
        expect.anything(),
      );
      expect(mock.history.post).toHaveLength(1);
    });
  });

  describe('the modal learn-more-click event', () => {
    it('tracks the learn more event with the state label and group id property', () => {
      createComponent({ requested: false });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('learn-more-click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_learn_more_explore_premium_modal',
        { label: REQUEST_STATE.NOT_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });

  describe('the modal hide event', () => {
    it('tracks a dismiss when no request was made during this open', () => {
      createComponent({ requested: false });
      findItem().vm.$emit('action');
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('hide');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'dismiss_explore_premium_modal',
        { label: REQUEST_STATE.NOT_REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });

    it('does not track a dismiss when a request was made during this open', async () => {
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_OK);
      createComponent({ requested: false });
      findItem().vm.$emit('action');
      findModal().vm.$emit('request');
      await waitForPromises();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('hide');

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        'dismiss_explore_premium_modal',
        expect.anything(),
        expect.anything(),
      );
    });

    it('tracks a dismiss when reopening an already-requested modal without acting', () => {
      document.cookie = `${COOKIE_KEY}=1`;
      createComponent({ requested: true });
      findItem().vm.$emit('action');
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('hide');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'dismiss_explore_premium_modal',
        { label: REQUEST_STATE.REQUESTED, property: String(GROUP_ID) },
        undefined,
      );
    });
  });
});
