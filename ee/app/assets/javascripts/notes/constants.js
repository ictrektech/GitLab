import { s__ } from '~/locale';

export * from '~/notes/constants';

export const MAX_REQUEST_TIMEOUT = 1000 * 15; // 15 seconds

export const DUO_CODE_REVIEW_DEPTH_LABELS = {
  standard: s__('DuoCodeReview|Standard review'),
  deep: s__('DuoCodeReview|Deep review'),
};
