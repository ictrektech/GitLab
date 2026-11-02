import { formatDate } from '~/lib/utils/datetime/date_format_utility';
import { formatNumber, n__, s__, sprintf } from '~/locale';

// `expiresOn` is the last day of the trial, in UTC.
export const trialDateText = (expiresOn) => formatDate(expiresOn, 'mmm d, yyyy', true);

export const freeCreditsText = (count) =>
  sprintf(n__('Orbit|%{count} credit', 'Orbit|%{count} credits', count), {
    count: formatNumber(count),
  });

export const daysText = (count) =>
  sprintf(n__('Orbit|%{count} day', 'Orbit|%{count} days', count), { count });

export const turnOnOfferText = (offer) => {
  if (!offer) return s__('Orbit|Trial when turned on');

  const { initialCredits } = offer;

  return sprintf(
    n__(
      'Orbit|%{credits} credit when turned on',
      'Orbit|%{credits} credits when turned on',
      initialCredits,
    ),
    { credits: formatNumber(initialCredits) },
  );
};
