import * as Sentry from '~/sentry/sentry_browser_wrapper';

/**
 * Captures an exception and sends it to Sentry, always tagging
 * it with feature_category: 'chat_engine'.
 *
 * @param {Error|unknown} error
 * @param {Object} [options={}] - Additional Sentry hint options (extra, fingerprint, level, tags, …)
 */
export const captureExceptionForDuoChat = (error, options = {}) => {
  Sentry.captureException(error, {
    ...options,
    tags: {
      ...options.tags,
      feature_category: 'chat_engine',
    },
  });
};
