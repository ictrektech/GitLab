import axios from '~/lib/utils/axios_utils';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import { groupCalloutsPath } from '~/lib/utils/path_helpers/user';
import { getCookie, setCookie } from '~/lib/utils/common_utils';

export const REQUEST_STATE = {
  NOT_REQUESTED: 'not_requested',
  REQUESTED: 'requested',
  PREVIOUSLY_REQUESTED: 'previously_requested',
};

export const PAINTED_DOOR_FEATURES = {
  DUO_PANEL: 'duo_panel_request_painted_door',
  EXPLORE_PREMIUM: 'explore_premium_request_painted_door',
};

const getStorageKey = ({ feature, groupId }) => `painted_door_${feature}_${groupId}`;

// GitLab has no product-session concept, so "this session" is approximated by a cookie set on
// success: SessionsController#destroy clears it on sign-out, and it expires after a day otherwise.
export const getInitialRequestState = ({ feature, groupId, requested }) => {
  if (getCookie(getStorageKey({ feature, groupId })) !== undefined) {
    return REQUEST_STATE.REQUESTED;
  }

  return requested ? REQUEST_STATE.PREVIOUSLY_REQUESTED : REQUEST_STATE.NOT_REQUESTED;
};

export const recordRequest = ({ feature, groupId }) =>
  axios
    .post(groupCalloutsPath(), { feature_name: feature, group_id: groupId })
    .then(() => {
      setCookie(getStorageKey({ feature, groupId }), '1', { expires: 1 });
    })
    .catch((error) => {
      captureException(error);
    });
