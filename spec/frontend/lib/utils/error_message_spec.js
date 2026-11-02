import { parseErrorMessage, convertPayloadErrors } from '~/lib/utils/error_message';

const defaultErrorMessage = 'Default error message';
const errorMessage = 'Returned error message';

const generateErrorWithMessage = (message) => {
  return {
    message,
  };
};

describe('parseErrorMessage', () => {
  const ufErrorPrefix = 'Foo:';
  beforeEach(() => {
    gon.uf_error_prefix = ufErrorPrefix;
  });

  it.each`
    error                                 | expectedResult
    ${`${ufErrorPrefix} ${errorMessage}`} | ${errorMessage}
    ${`${errorMessage} ${ufErrorPrefix}`} | ${defaultErrorMessage}
    ${errorMessage}                       | ${defaultErrorMessage}
    ${undefined}                          | ${defaultErrorMessage}
    ${''}                                 | ${defaultErrorMessage}
  `(
    'properly parses "$error" error object and returns "$expectedResult"',
    ({ error, expectedResult }) => {
      const errorObject = generateErrorWithMessage(error);
      expect(parseErrorMessage(errorObject, defaultErrorMessage)).toEqual(expectedResult);
    },
  );

  it.each`
    error                                                           | defaultMessage         | expectedResult
    ${undefined}                                                    | ${defaultErrorMessage} | ${defaultErrorMessage}
    ${''}                                                           | ${defaultErrorMessage} | ${defaultErrorMessage}
    ${{}}                                                           | ${defaultErrorMessage} | ${defaultErrorMessage}
    ${generateErrorWithMessage(errorMessage)}                       | ${undefined}           | ${''}
    ${generateErrorWithMessage(`${ufErrorPrefix} ${errorMessage}`)} | ${undefined}           | ${errorMessage}
    ${generateErrorWithMessage(errorMessage)}                       | ${''}                  | ${''}
    ${generateErrorWithMessage(`${ufErrorPrefix} ${errorMessage}`)} | ${''}                  | ${errorMessage}
  `(
    'properly handles the edge case of error="$error" and defaultMessage="$defaultMessage"',
    ({ error, defaultMessage, expectedResult }) => {
      expect(parseErrorMessage(error, defaultMessage)).toEqual(expectedResult);
    },
  );
});

describe('convertPayloadErrors', () => {
  describe('when the payload has errors', () => {
    it('returns the error as the message when there is only one', () => {
      const { message } = convertPayloadErrors([errorMessage], {
        defaultMessage: defaultErrorMessage,
      });

      expect(message).toBe(errorMessage);
    });

    it('joins multiple errors into the message', () => {
      const { message } = convertPayloadErrors(['First error.', 'Second error.'], {
        defaultMessage: defaultErrorMessage,
      });

      expect(message).toBe('First error. Second error.');
    });

    it('returns an Error with the joined message so Sentry gets a stack trace', () => {
      const { error } = convertPayloadErrors(['First error.', 'Second error.']);

      expect(error).toBeInstanceOf(Error);
      expect(error.message).toBe('First error. Second error.');
    });

    it('skips empty errors', () => {
      const { message } = convertPayloadErrors(['', 'First error.', null, 'Second error.']);

      expect(message).toBe('First error. Second error.');
    });
  });

  describe.each([[[]], [undefined], [null], [['']]])('when errors is %p', (errors) => {
    it('falls back to the default message', () => {
      const { message, error } = convertPayloadErrors(errors, {
        defaultMessage: defaultErrorMessage,
      });

      expect(message).toBe(defaultErrorMessage);
      expect(error).toBeInstanceOf(Error);
      expect(error.message).toBe(defaultErrorMessage);
    });

    it('returns an empty message when no default message is given', () => {
      expect(convertPayloadErrors(errors).message).toBe('');
    });
  });
});
