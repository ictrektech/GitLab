import { s__ } from '~/locale';

export const SECRETS_MANAGER_CTA_VIEW_EVENT = 'view_secrets_manager_cta_in_variables';
export const SECRETS_MANAGER_CTA_CLICK_EVENT = 'click_secrets_manager_cta_in_variables';
export const SECRETS_MANAGER_CTA_LABEL_LEARN_MORE = 'learn_more';
export const SECRETS_MANAGER_CTA_LABEL_TRY = 'try_gitlab_secrets_manager_ci_variable';
export const SECRETS_MANAGER_CTA_LABEL_VIEW = 'view_gitlab_secrets_manager_ci_variable';
export const SECRETS_MANAGER_CTA_LABEL_REQUEST = 'request_gitlab_secrets_manager_ci_variable';
export const SECRETS_MANAGER_CTA_LABEL_INFO = 'info_gitlab_secrets_manager_ci_variable';
export const SECRETS_MANAGER_REQUEST_MODAL_ID = 'secrets-manager-request-modal';

export const VARIANT_VIEW = 'view';
export const VARIANT_TRY = 'try';
export const VARIANT_REQUEST = 'request';
export const VARIANT_INFO = 'info';

export const I18N_REQUEST_TEXT = s__('SecretsManager|Request GitLab Secrets Manager');
const I18N_INTRODUCTION_BODY = s__(
  'SecretsManager|Use GitLab Secrets Manager to store your sensitive credentials, and then safely use them in your processes. Secrets could be access tokens, database credentials, private keys, or similar. %{linkStart}Learn more.%{linkEnd}',
);
const I18N_ENABLED_BODY = s__(
  'SecretsManager|Store your sensitive credentials in GitLab Secrets Manager and safely use them in your processes. Unlike CI/CD variables, which are always available to jobs by default, secrets must be explicitly requested by a job. %{linkStart}Learn more.%{linkEnd}',
);

export const VARIANTS = {
  [VARIANT_VIEW]: {
    title: s__('SecretsManager|Are you creating a new secret?'),
    body: I18N_ENABLED_BODY,
    icon: 'work-item-enhancement',
    showNewBadge: false,
    actionText: s__('SecretsManager|View GitLab Secrets Manager'),
    actionLabel: SECRETS_MANAGER_CTA_LABEL_VIEW,
  },
  [VARIANT_INFO]: {
    title: s__('SecretsManager|Are you creating a new secret?'),
    body: I18N_ENABLED_BODY,
    icon: 'work-item-enhancement',
    showNewBadge: false,
    actionText: null,
    actionLabel: SECRETS_MANAGER_CTA_LABEL_INFO,
  },
  [VARIANT_TRY]: {
    title: s__('SecretsManager|GitLab Secrets Manager'),
    body: I18N_INTRODUCTION_BODY,
    icon: 'secrets-manager',
    showNewBadge: true,
    actionText: s__('SecretsManager|Try GitLab Secrets Manager'),
    actionLabel: SECRETS_MANAGER_CTA_LABEL_TRY,
  },
  [VARIANT_REQUEST]: {
    title: s__('SecretsManager|GitLab Secrets Manager'),
    body: I18N_INTRODUCTION_BODY,
    icon: 'secrets-manager',
    showNewBadge: true,
    actionText: I18N_REQUEST_TEXT,
    actionLabel: SECRETS_MANAGER_CTA_LABEL_REQUEST,
  },
};
