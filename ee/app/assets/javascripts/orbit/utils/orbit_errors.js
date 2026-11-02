import { HTTP_STATUS_FORBIDDEN, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';

export const ORBIT_ERROR_KIND = {
  FORBIDDEN: 'forbidden',
  CLIENT: 'client',
  SERVER: 'server',
};

// The Orbit API answers 4xx for expected states (no license, no default group, rate limits).
export const orbitErrorKind = (error) => {
  const status = error?.response?.status;

  if (status === HTTP_STATUS_FORBIDDEN) return ORBIT_ERROR_KIND.FORBIDDEN;
  if (status && status < HTTP_STATUS_INTERNAL_SERVER_ERROR) return ORBIT_ERROR_KIND.CLIENT;
  return ORBIT_ERROR_KIND.SERVER;
};

// Rate limit bodies put the text in message.error.
export const orbitApiMessage = ({ message } = {}) =>
  typeof message === 'string' ? message : message?.error;

export const orbitErrorMessage = (error, fallback) =>
  (orbitErrorKind(error) === ORBIT_ERROR_KIND.CLIENT && orbitApiMessage(error.response.data)) ||
  fallback;
