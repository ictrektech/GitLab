import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { parseOrbitPlatform } from 'ee/orbit/access/platform';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('parseOrbitPlatform', () => {
  it.each([undefined, ''])('defaults to GitLab.com when the attribute is %p', (json) => {
    expect(parseOrbitPlatform(json)).toEqual({ saas: true, instance: null });
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  it('parses the platform and its instance', () => {
    const json = JSON.stringify({ saas: false, instance: { state: 'TRIAL_ELIGIBLE' } });

    expect(parseOrbitPlatform(json)).toEqual({
      saas: false,
      instance: { state: 'TRIAL_ELIGIBLE' },
    });
  });

  it('keeps the instance null when the attribute omits it', () => {
    expect(parseOrbitPlatform(JSON.stringify({ saas: false }))).toEqual({
      saas: false,
      instance: null,
    });
  });

  it.each(['not json', 'null'])('defaults and reports to Sentry for %p', (json) => {
    expect(parseOrbitPlatform(json)).toEqual({ saas: true, instance: null });
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
  });

  it('falls back to GitLab.com when saas is not a boolean', () => {
    const json = JSON.stringify({ saas: 'yes', instance: { state: 'UNLICENSED' } });

    expect(parseOrbitPlatform(json)).toEqual({ saas: true, instance: { state: 'UNLICENSED' } });
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });
});
