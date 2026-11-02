import { getAgentStatusFillClass } from 'ee/ai/duo_agents_platform/utils';

// A created session is starting up, so it shares the running color and pulses with it.
const PULSING_STATUSES = ['CREATED', 'RUNNING'];
const PULSE_CLASS = 'motion-safe:gl-animate-[session-pill-pulse_2s_ease-in-out_infinite]';

export const getStatusDotClass = (status) =>
  PULSING_STATUSES.includes(status)
    ? `${getAgentStatusFillClass('RUNNING')} ${PULSE_CLASS}`
    : getAgentStatusFillClass(status);
