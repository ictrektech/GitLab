import {
  ORBIT_ERROR_KIND,
  orbitApiMessage,
  orbitErrorKind,
  orbitErrorMessage,
} from 'ee/orbit/utils/orbit_errors';

const httpError = (status, data = {}) => ({ response: { status, data } });

describe('orbit_errors', () => {
  describe('orbitErrorKind', () => {
    it.each`
      scenario             | error                   | kind
      ${'a 403'}           | ${httpError(403)}       | ${ORBIT_ERROR_KIND.FORBIDDEN}
      ${'a 422'}           | ${httpError(422)}       | ${ORBIT_ERROR_KIND.CLIENT}
      ${'a 429'}           | ${httpError(429)}       | ${ORBIT_ERROR_KIND.CLIENT}
      ${'a 503'}           | ${httpError(503)}       | ${ORBIT_ERROR_KIND.SERVER}
      ${'a network error'} | ${new Error('offline')} | ${ORBIT_ERROR_KIND.SERVER}
    `('returns $kind for $scenario', ({ error, kind }) => {
      expect(orbitErrorKind(error)).toBe(kind);
    });
  });

  describe('orbitApiMessage', () => {
    it.each`
      scenario               | body                                   | message
      ${'a text message'}    | ${{ message: 'Unknown entity' }}       | ${'Unknown entity'}
      ${'a rate limit body'} | ${{ message: { error: 'Slow down' } }} | ${'Slow down'}
      ${'no message'}        | ${{}}                                  | ${undefined}
    `('reads $scenario', ({ body, message }) => {
      expect(orbitApiMessage(body)).toBe(message);
    });
  });

  describe('orbitErrorMessage', () => {
    it.each`
      scenario                       | error                                                  | message
      ${'a 422 with an API message'} | ${httpError(422, { message: 'Unknown entity' })}       | ${'Unknown entity'}
      ${'a rate limit'}              | ${httpError(429, { message: { error: 'Slow down' } })} | ${'Slow down'}
      ${'a 4xx with no API message'} | ${httpError(429)}                                      | ${'Fallback'}
      ${'a 403 with an API message'} | ${httpError(403, { message: '403 Forbidden' })}        | ${'Fallback'}
      ${'a 503 with an API message'} | ${httpError(503, { message: 'Down' })}                 | ${'Fallback'}
    `('returns $message for $scenario', ({ error, message }) => {
      expect(orbitErrorMessage(error, 'Fallback')).toBe(message);
    });
  });
});
