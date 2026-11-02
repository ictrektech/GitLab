import MockAdapter from 'axios-mock-adapter';
import axios from '~/lib/utils/axios_utils';
import * as commonUtils from '~/lib/utils/common_utils';
import { getCookie, removeCookie } from '~/lib/utils/common_utils';
import { groupCalloutsPath } from '~/lib/utils/path_helpers/user';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  REQUEST_STATE,
  PAINTED_DOOR_FEATURES,
  getInitialRequestState,
  recordRequest,
} from 'ee/painted_door_request/utils';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('painted door request utils', () => {
  const feature = PAINTED_DOOR_FEATURES.DUO_PANEL;
  const groupId = 123;
  const cookieKey = `painted_door_${feature}_${groupId}`;

  let mock;

  beforeEach(() => {
    mock = new MockAdapter(axios);
  });

  afterEach(() => {
    mock.restore();
    removeCookie(cookieKey);
  });

  describe('getInitialRequestState', () => {
    it('returns NOT_REQUESTED when not requested and the cookie is absent', () => {
      expect(getInitialRequestState({ feature, groupId, requested: false })).toBe(
        REQUEST_STATE.NOT_REQUESTED,
      );
    });

    it('returns REQUESTED when the cookie is present but requested is still the page-load false', () => {
      document.cookie = `${cookieKey}=1`;

      expect(getInitialRequestState({ feature, groupId, requested: false })).toBe(
        REQUEST_STATE.REQUESTED,
      );
    });

    it('returns REQUESTED when requested and the cookie is present', () => {
      document.cookie = `${cookieKey}=1`;

      expect(getInitialRequestState({ feature, groupId, requested: true })).toBe(
        REQUEST_STATE.REQUESTED,
      );
    });

    it('returns PREVIOUSLY_REQUESTED when requested and the cookie is absent', () => {
      expect(getInitialRequestState({ feature, groupId, requested: true })).toBe(
        REQUEST_STATE.PREVIOUSLY_REQUESTED,
      );
    });
  });

  describe('recordRequest', () => {
    it('writes the cookie with a 1-day expiry and posts the callout payload', async () => {
      jest.spyOn(commonUtils, 'setCookie');
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_OK);

      await recordRequest({ feature, groupId });

      expect(getCookie(cookieKey)).toBe('1');
      expect(commonUtils.setCookie).toHaveBeenCalledWith(cookieKey, '1', { expires: 1 });
      expect(mock.history.post).toHaveLength(1);
      expect(JSON.parse(mock.history.post[0].data)).toEqual({
        feature_name: feature,
        group_id: groupId,
      });
    });

    it('captures the error, resolves, and does not write the cookie when the POST fails', async () => {
      mock.onPost(groupCalloutsPath()).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

      await expect(recordRequest({ feature, groupId })).resolves.toBeUndefined();

      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      expect(getCookie(cookieKey)).toBeUndefined();
    });
  });
});
