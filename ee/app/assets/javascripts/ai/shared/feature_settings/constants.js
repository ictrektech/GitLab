/* eslint-disable @gitlab/require-i18n-strings */
import { s__ } from '~/locale';

export const RELEASE_STATES = {
  GA: 'GA',
  BETA: 'BETA',
  EXPERIMENT: 'EXPERIMENT',
};

export const RELEASE_STATE_DISPLAY_ORDER = {
  [RELEASE_STATES.GA]: 1,
  [RELEASE_STATES.BETA]: 2,
  [RELEASE_STATES.EXPERIMENT]: 3,
};

export const DUO_MAIN_FEATURES = {
  CODE_SUGGESTIONS: 'Code Suggestions',
  DUO_CHAT: 'GitLab Duo Chat',
  MERGE_REQUESTS: 'GitLab Duo for merge requests',
  ISSUES: 'GitLab Duo for issues',
  OTHER_GITLAB_DUO_FEATURES: 'Other GitLab Duo features',
  AGENT_PLATFORM: 'GitLab Duo Agent Platform',
};

export const FEATURE_SETTINGS_FIXED_LOADER_WIDTH = '440';
export const FEATURE_SETTINGS_VARIABLE_LOADER_WIDTHS = ['200', '80', '150'];

// Code Review has one model setting per review depth, in display order.
export const DUO_CODE_REVIEW_DEPTHS = {
  review_merge_request_dap: {
    label: s__('AdminAIPoweredFeatures|Standard'),
    description: s__('AdminAIPoweredFeatures|Efficient review, limited context'),
  },
  review_merge_request_dap_deep: {
    label: s__('AdminAIPoweredFeatures|Deep'),
    description: s__('AdminAIPoweredFeatures|Extensive analysis, more context'),
  },
};

export const DUO_CODE_REVIEW_DEPTHS_HEADER_KEY = 'duo_code_review_depths';
