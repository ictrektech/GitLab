import { __, s__ } from '~/locale';
import {
  ACCESS_SELECTED_MEMBERSHIPS_ENUM,
  ACCESS_USER_ENUM,
} from '~/vue_shared/access_tokens/constants';

export const CONFIRM_MODAL = s__(
  'AuthorizedApplication|Are you sure you want to renew this secret? Any applications using the old secret will no longer be able to authenticate with GitLab.',
);
export const CONFIRM_MODAL_TITLE = s__('AuthorizedApplication|Renew secret?');
export const COPY_SECRET = __('Copy secret');
export const DESCRIPTION_SECRET = __(
  'This is the only time the secret is accessible. Copy the secret and store it securely.',
);
export const RENEW_SECRET = s__('AuthorizedApplication|Renew secret');
export const RENEW_SECRET_FAILURE = s__(
  'AuthorizedApplication|There was an error trying to renew the application secret. Please try again.',
);
export const RENEW_SECRET_SUCCESS = s__(
  'AuthorizedApplication|Application secret was successfully renewed.',
);
export const WARNING_NO_SECRET = __(
  'The secret is only available when you create the application or renew the secret.',
);

export const GRANULAR_SCOPES_INPUT_PREFIX = 'authn_oauth_application[granular_scopes]';

// Maps the access level an application declares to the scope key the shared picker renders
export const SCOPE_KEY_BY_ACCESS_LEVEL = {
  [ACCESS_SELECTED_MEMBERSHIPS_ENUM]: 'namespace',
  [ACCESS_USER_ENUM]: 'user',
};
