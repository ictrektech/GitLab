export const FUNCTIONAL_VERIFICATION_STATUS = {
  NOT_RUN: 'NOT_RUN',
  RUNNING: 'RUNNING',
  PASSED: 'PASSED',
  FAILED: 'FAILED',
};

export const MODEL_PROVIDERS = {
  SELF_HOSTED: 'self_hosted',
  GITLAB_MANAGED: 'vendored',
  DISABLED: 'disabled',
};

export const AGENTIC_CHAT_FEATURE = 'duo_agent_platform_agentic_chat';

export const NAMESPACES_PAGE_SIZE = 20;

export const CHECK_TYPES = {
  AGENTIC_CHAT: 'AGENTIC_CHAT',
};

export const NOT_RUN_STATE = {
  state: FUNCTIONAL_VERIFICATION_STATUS.NOT_RUN,
  checkedAt: null,
};

// Must match the backend's GOALS[AGENTIC_CHAT] (create_functional_verification_workflow.rb):
// the WS start request re-sends this same text as the chat turn.
export const VERIFICATION_GOAL = 'How do I create a project in GitLab?';

// Backstop for a socket that hangs with no message or close event at all. Mirrors
// Ai::DuoAgentPlatform::FunctionalVerificationRunService::RUN_TIMEOUT.
export const VERIFICATION_WATCHDOG_MS = 100 * 1000;
