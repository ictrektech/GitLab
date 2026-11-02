import { s__ } from '~/locale';

export const AGENT_SESSION_INBOX_STATUS_LABELS = {
  INPUT_REQUIRED: s__('DuoAgentsPlatform|Waiting for input'),
  IDLE: s__('DuoAgentPlatform|Idle'),
  PLAN_APPROVAL_REQUIRED: s__('DuoAgentsPlatform|Approval gate'),
  TOOL_CALL_APPROVAL_REQUIRED: s__('DuoAgentsPlatform|Confirm action'),
  STOPPED: s__('DuoAgentsPlatform|Canceled'),
};
