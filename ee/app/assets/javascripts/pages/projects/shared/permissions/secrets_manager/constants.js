import { s__ } from '~/locale';

export const PERMISSION_CATEGORY_ROLE = 'ROLE';
export const PERMISSION_CATEGORY_USER = 'USER';

const CREATE_LABEL = s__('SecretsManagerPermissions|Create');
const UPDATE_LABEL = s__('SecretsManagerPermissions|Update');

export const SCOPE_ORDER = ['READ', 'READ_VALUE', 'CREATE', 'WRITE', 'DELETE'];
export const SCOPE_LABELS = {
  READ: s__('SecretsManagerPermissions|Read metadata'),
  READ_VALUE: s__('SecretsManagerPermissions|Read value'),
  CREATE: CREATE_LABEL,
  // The API's WRITE action grants create and update, so the table shows both scopes.
  WRITE: [CREATE_LABEL, UPDATE_LABEL].join(', '),
  DELETE: s__('SecretsManagerPermissions|Delete'),
};

export const ALERT_CONTAINER_CLASSNAME = 'js-secrets-manager-permissions-alert-container';
export const ALERT_CONTAINER_SELECTOR = `.${ALERT_CONTAINER_CLASSNAME}`;
