import { GROUP_FILTER_EXCLUDED, GROUP_FILTER_OPTIONS } from 'ee/orbit/shared/groups/constants';

// The orbit.access field resolves for at most 10 groups in one request.
export const GROUP_STATUS_PAGE_SIZE = 10;

// Only an administrator excludes groups, on the Admin area Orbit page.
export const GROUP_STATUS_FILTER_OPTIONS = GROUP_FILTER_OPTIONS.filter(
  ({ value }) => value !== GROUP_FILTER_EXCLUDED,
);
