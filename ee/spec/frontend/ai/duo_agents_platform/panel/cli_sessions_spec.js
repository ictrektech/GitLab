import { isIdleCliSession } from 'ee/ai/duo_agents_platform/panel/cli_sessions';

describe('isIdleCliSession', () => {
  describe('when the session is an interactive CLI session', () => {
    let session;

    beforeEach(() => {
      session = { sourceType: 'DUO_CLI_INTERACTIVE' };
    });

    it.each`
      status                           | expected
      ${'INPUT_REQUIRED'}              | ${true}
      ${'FAILED'}                      | ${false}
      ${'FINISHED'}                    | ${false}
      ${'RUNNING'}                     | ${false}
      ${'PLAN_APPROVAL_REQUIRED'}      | ${false}
      ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${false}
    `('returns $expected for status $status', ({ status, expected }) => {
      expect(isIdleCliSession({ ...session, status })).toBe(expected);
    });
  });

  describe('when the session is in INPUT_REQUIRED', () => {
    it.each`
      reason                                                     | sourceType               | expected
      ${'sourceType is DUO_CLI_INTERACTIVE'}                     | ${'DUO_CLI_INTERACTIVE'} | ${true}
      ${'sourceType is DUO_CLI_ACP'}                             | ${'DUO_CLI_ACP'}         | ${true}
      ${'sourceType is DUO_CLI_RUN (headless, not interactive)'} | ${'DUO_CLI_RUN'}         | ${false}
      ${'sourceType is the retired CLI literal'}                 | ${'CLI'}                 | ${false}
      ${'sourceType is not CLI'}                                 | ${'SLACK'}               | ${false}
      ${'sourceType is null'}                                    | ${null}                  | ${false}
      ${'sourceType is undefined'}                               | ${undefined}             | ${false}
    `('returns $expected when $reason', ({ sourceType, expected }) => {
      expect(isIdleCliSession({ sourceType, status: 'INPUT_REQUIRED' })).toBe(expected);
    });
  });
});
