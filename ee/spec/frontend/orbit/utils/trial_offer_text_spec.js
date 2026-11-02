import {
  daysText,
  freeCreditsText,
  trialDateText,
  turnOnOfferText,
} from 'ee/orbit/utils/trial_offer_text';

describe('freeCreditsText', () => {
  it.each`
    count   | text
    ${1}    | ${'1 credit'}
    ${1000} | ${'1,000 credits'}
  `('returns "$text" for $count', ({ count, text }) => {
    expect(freeCreditsText(count)).toBe(text);
  });
});

describe('daysText', () => {
  it.each`
    count | text
    ${1}  | ${'1 day'}
    ${30} | ${'30 days'}
  `('returns "$text" for $count', ({ count, text }) => {
    expect(daysText(count)).toBe(text);
  });
});

describe('turnOnOfferText', () => {
  it.each`
    offer                                         | text
    ${{ durationDays: 30, initialCredits: 1 }}    | ${'1 credit when turned on'}
    ${{ durationDays: 30, initialCredits: 1000 }} | ${'1,000 credits when turned on'}
    ${null}                                       | ${'Trial when turned on'}
  `('returns "$text" for the offer $offer', ({ offer, text }) => {
    expect(turnOnOfferText(offer)).toBe(text);
  });
});

describe('trialDateText', () => {
  it('formats the last day of the trial in UTC', () => {
    expect(trialDateText('2026-11-13')).toBe('Nov 13, 2026');
  });
});
