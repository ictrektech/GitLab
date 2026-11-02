import { formatDate, toISODateFormat } from '~/lib/utils/datetime/date_format_utility';

// The backend counts runs created in the last 30 * 24 hours and groups them by UTC date,
// so the window spans 31 dates and the oldest one is partial.
const DAILY_VOLUME_DATES = 31;

export const successRate = ({ finishedRuns, failedRuns }) => {
  const endedRuns = finishedRuns + failedRuns;

  return endedRuns ? Math.floor((finishedRuns / endedRuns) * 100) : null;
};

export const fillDailyVolume = (dailyVolume) => {
  const now = new Date();
  const runsByDate = Object.fromEntries(dailyVolume.map(({ date, runs }) => [date, runs]));

  return Array.from({ length: DAILY_VOLUME_DATES }, (_, index) => {
    const date = new Date(now);
    date.setUTCDate(date.getUTCDate() - (DAILY_VOLUME_DATES - 1 - index));

    return [formatDate(date, 'mmm d', true), runsByDate[toISODateFormat(date, true)] ?? 0];
  });
};
