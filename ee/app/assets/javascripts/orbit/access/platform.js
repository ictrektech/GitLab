import * as Sentry from '~/sentry/sentry_browser_wrapper';

const DEFAULT_PLATFORM = { saas: true, instance: null };

// A missing or invalid attribute must never show the GitLab Self-Managed UI on GitLab.com.
export const parseOrbitPlatform = (json) => {
  if (!json) return { ...DEFAULT_PLATFORM };

  try {
    const { saas, instance } = JSON.parse(json);
    return { saas: typeof saas === 'boolean' ? saas : true, instance: instance ?? null };
  } catch (error) {
    Sentry.captureException(error);
    return { ...DEFAULT_PLATFORM };
  }
};
