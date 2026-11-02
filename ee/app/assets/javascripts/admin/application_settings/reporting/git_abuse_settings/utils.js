import { parseBoolean } from '@gitlab/frontend-utils';

export const parseFormProps = ({
  maxNumberOfRepositoryDownloads,
  maxNumberOfRepositoryDownloadsWithinTimePeriod,
  gitRateLimitUsersAllowlist,
  gitRateLimitUsersAlertlist,
  autoBanUserOnExcessiveProjectsDownload,
}) => ({
  maxNumberOfRepositoryDownloads: parseInt(maxNumberOfRepositoryDownloads, 10),
  maxNumberOfRepositoryDownloadsWithinTimePeriod: parseInt(
    maxNumberOfRepositoryDownloadsWithinTimePeriod,
    10,
  ),
  gitRateLimitUsersAllowlist: JSON.parse(gitRateLimitUsersAllowlist),
  gitRateLimitUsersAlertlist: JSON.parse(gitRateLimitUsersAlertlist),
  autoBanUserOnExcessiveProjectsDownload: parseBoolean(autoBanUserOnExcessiveProjectsDownload),
});
