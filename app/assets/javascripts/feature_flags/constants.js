import { s__ } from '~/locale';

export const ROLLOUT_STRATEGY_ALL_USERS = 'default';
export const ROLLOUT_STRATEGY_PERCENT_ROLLOUT = 'gradualRolloutUserId';
export const ROLLOUT_STRATEGY_FLEXIBLE_ROLLOUT = 'flexibleRollout';
export const ROLLOUT_STRATEGY_USER_ID = 'userWithId';
export const ROLLOUT_STRATEGY_GITLAB_USER_LIST = 'gitlabUserList';

export const PERCENT_ROLLOUT_GROUP_ID = 'default';
export const GROUP_ID_REGEX = /^[a-z]{1,32}$/;
export const GROUP_ID_DESCRIPTION = s__(
  'FeatureFlags|Strategies with the same group ID and percentage select the same users.',
);
export const GROUP_ID_INVALID_FEEDBACK = s__(
  'FeatureFlags|Group ID must contain 1 to 32 lowercase letters (a-z).',
);
export const GROUP_ID_LABEL = s__('FeatureFlags|Group ID');

export const ALL_ENVIRONMENTS_NAME = '*';

export const NEW_VERSION_FLAG = 'new_version_flag';
export const LEGACY_FLAG = 'legacy_flag';

export const EMPTY_PARAMETERS = { parameters: {}, userListId: undefined };

export const STRATEGY_SELECTIONS = [
  {
    value: ROLLOUT_STRATEGY_ALL_USERS,
    text: s__('FeatureFlags|All users'),
  },
  {
    value: ROLLOUT_STRATEGY_FLEXIBLE_ROLLOUT,
    text: s__('FeatureFlags|Percent rollout'),
  },
  {
    value: ROLLOUT_STRATEGY_PERCENT_ROLLOUT,
    text: s__('FeatureFlags|Percent of users'),
  },
  {
    value: ROLLOUT_STRATEGY_USER_ID,
    text: s__('FeatureFlags|User IDs'),
  },
  {
    value: ROLLOUT_STRATEGY_GITLAB_USER_LIST,
    text: s__('FeatureFlags|User List'),
  },
];
