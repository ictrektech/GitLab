/**
 * Utility to parse an error object returned from API.
 *
 *
 * @param { Object } error - An error object directly from API response
 * @param { string } error.message - The error message, returned from API.
 * @param { string } defaultMessage - Default user-facing error message
 * @returns { string } - A transformed user-facing error message, or defaultMessage
 */
export const parseErrorMessage = (error = {}, defaultMessage = '') => {
  const messageString = error.message || '';
  return messageString.startsWith(window.gon.uf_error_prefix)
    ? messageString.replace(window.gon.uf_error_prefix, '').trim()
    : defaultMessage;
};

/**
 * Converts the `errors` array of a GraphQL mutation payload into the shape
 * `createAlert` expects. `error` is a real `Error` so Sentry gets a stack trace.
 *
 * @param { string[] } errors - The `errors` array from a mutation payload
 * @param { Object } options
 * @param { string } options.defaultMessage - Used when there is no error message
 * @returns { { message: string, error: Error } } - All non-empty errors joined with a space, and an Error wrapping that message
 */
export const convertPayloadErrors = (errors, { defaultMessage = '' } = {}) => {
  const messages = Array.isArray(errors) ? errors.filter(Boolean) : [];
  const message = messages.join(' ') || defaultMessage;

  return { message, error: new Error(message) };
};
