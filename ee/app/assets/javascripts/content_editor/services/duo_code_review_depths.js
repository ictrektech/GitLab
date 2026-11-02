import { s__ } from '~/locale';
import { COMMANDS } from '~/content_editor/constants';

export const DUO_CODE_REVIEW_DEPTHS = [
  {
    name: 'standard',
    header: s__('DuoCodeReview|Standard'),
    description: s__('DuoCodeReview|Efficient review, limited context'),
  },
  {
    name: 'deep',
    header: s__('DuoCodeReview|Deep'),
    description: s__('DuoCodeReview|Extensive analysis, more context'),
  },
];

const REQUEST_REVIEW_COMMANDS = [
  COMMANDS.REQUEST_REVIEW,
  COMMANDS.ASSIGN_REVIEWER,
  COMMANDS.REVIEWER,
];

// The depth option the backend reads after `/request_review` (or an alias) and its reviewers.
const REQUEST_REVIEW_DEPTH_REGEX = new RegExp(
  `^(?:${REQUEST_REVIEW_COMMANDS.join('|')})\\s(?:.*\\s)?-(\\w*)$`,
);

// The backend ignores the depth unless the Duo Code Review bot is among the reviewers.
const DUO_CODE_REVIEW_BOT_REGEX = /(?:^|\s)@GitLabDuo(?=\s)/i;

export const isDuoCodeReviewDepthEnabled = () => Boolean(gon.features?.duoCodeReviewDeepFlow);

// Returns the typed depth query when `line` ends in a depth option for Duo, otherwise null.
export const findDuoCodeReviewDepthQuery = (line) => {
  if (!isDuoCodeReviewDepthEnabled() || !DUO_CODE_REVIEW_BOT_REGEX.test(line)) return null;

  return REQUEST_REVIEW_DEPTH_REGEX.exec(line)?.[1] ?? null;
};

export const getDuoCodeReviewDepths = (command) =>
  isDuoCodeReviewDepthEnabled() && REQUEST_REVIEW_COMMANDS.includes(command)
    ? DUO_CODE_REVIEW_DEPTHS
    : [];
