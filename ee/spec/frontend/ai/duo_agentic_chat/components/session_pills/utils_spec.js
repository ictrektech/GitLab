import { getStatusDotClass } from 'ee/ai/duo_agentic_chat/components/session_pills/utils';

describe('session_pills/utils', () => {
  describe('getStatusDotClass', () => {
    it.each`
      status                           | expected
      ${'CREATED'}                     | ${'gl-fill-status-info motion-safe:gl-animate-[session-pill-pulse_2s_ease-in-out_infinite]'}
      ${'RUNNING'}                     | ${'gl-fill-status-info motion-safe:gl-animate-[session-pill-pulse_2s_ease-in-out_infinite]'}
      ${'INPUT_REQUIRED'}              | ${'gl-fill-status-warning'}
      ${'PLAN_APPROVAL_REQUIRED'}      | ${'gl-fill-status-warning'}
      ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${'gl-fill-status-warning'}
      ${'PAUSED'}                      | ${'gl-fill-status-neutral'}
      ${'FINISHED'}                    | ${'gl-fill-status-success'}
      ${'FAILED'}                      | ${'gl-fill-status-danger'}
      ${'STOPPED'}                     | ${'gl-fill-status-neutral'}
      ${'UNKNOWN_FUTURE_STATUS'}       | ${'gl-fill-status-neutral'}
    `('maps $status to $expected', ({ status, expected }) => {
      expect(getStatusDotClass(status)).toBe(expected);
    });
  });
});
