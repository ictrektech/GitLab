import { __, s__ } from '~/locale';

// AiToolActionType GraphQL enum values. Used by the AI tool rules search filter.
const ACTION_TYPE_READ = 'READ';
const ACTION_TYPE_WRITE = 'WRITE';
const ACTION_TYPE_DESTROY = 'DESTROY';

// Filtered-search token type for the action filter.
export const TOKEN_TYPE_ACTION = 'action';

// Static options for the action token, mapping a human title to the enum value.
export const ACTION_TOKEN_OPTIONS = [
  { value: ACTION_TYPE_READ, title: s__('AiGovernance|Read') },
  { value: ACTION_TYPE_WRITE, title: s__('AiGovernance|Write') },
  { value: ACTION_TYPE_DESTROY, title: s__('AiGovernance|Destroy') },
];

// AiGovernanceAgentClass GraphQL enum values. Drives the dashboard agent-class
// filter and every card query that segments by it.
export const AGENT_CLASS_ALL = 'ALL';
export const AGENT_CLASS_INTERNAL_DAP = 'INTERNAL_DAP';
export const AGENT_CLASS_EXTERNAL = 'EXTERNAL';

// AiGovernanceSessionSource GraphQL enum values, as shown on dashboard session rows.
export const SESSION_SOURCE_LABELS = {
  GITLAB_DUO: s__('AiGovernance|GitLab Duo'),
  CLAUDE_CODE_COMPLIANCE_API: s__('AiGovernance|Claude Code (Compliance API)'),
  CLAUDE_CODE_GLAB: s__('AiGovernance|Claude Code (glab)'),
};

// AiGovernanceMetricsTimeframe GraphQL enum values. The enum also accepts
// LAST_24_HOURS, which needs an hourly chart axis before it can be offered.
export const TIMEFRAME_LAST_SEVEN_DAYS = 'LAST_7_DAYS';
export const TIMEFRAME_LAST_THIRTY_DAYS = 'LAST_30_DAYS';

// SkillGuard publishes as a SAST report, so `report_type` cannot distinguish it.
// The scanner `external_id` is the discriminator, and the project-scope deep-link param.
export const SKILLGUARD_SCANNER_ID = 'skillguard';

// Group-scope deep-link param: the group Vulnerability Report offers an identifier
// token but no scanner one. Matches `primaryIdentifierName` in the analyzer's convert.go.
export const SKILLGUARD_IDENTIFIER_NAME = 'SkillGuard Skill Analysis';

// Most severe first.
export const SKILLGUARD_SEVERITIES = ['critical', 'high', 'medium', 'low', 'unknown', 'info'];

// Severity-to-verdict mapping agreed on #629070, and the single source of truth for it.
// The analyzer publishes severity only, never the verdict, so this is a product
// convention rather than data. HIGH also covers the analyzer's DANGEROUS verdict, and
// severities absent here keep their own name instead of being guessed at.
export const SKILLGUARD_VERDICT_LABELS = {
  critical: s__('AiGovernance|malicious'),
  high: s__('AiGovernance|suspicious'),
};

// Whole sentences per verdict, so translators control case and word agreement.
export const SKILLGUARD_SKILL_TOOLTIPS = {
  critical: {
    skill: s__('AiGovernance|Malicious skill'),
    skillInProject: s__('AiGovernance|Malicious skill in %{project}'),
  },
  high: {
    skill: s__('AiGovernance|Suspicious skill'),
    skillInProject: s__('AiGovernance|Suspicious skill in %{project}'),
  },
};

// Product names for external agent types, keyed by the `agent_type` the backend
// stores (Ai::ExternalAgents::AgentIdentity::AGENT_TYPES), plus the reserved
// `gitlab_duo` slice. Humanizing would lowercase them, for example "Claude code".
export const AGENT_TYPE_LABELS = {
  gitlab_duo: __('GitLab Duo'),
  'claude-code': s__('AiGovernance|Claude Code'),
  cursor: s__('AiGovernance|Cursor'),
  opencode: s__('AiGovernance|OpenCode'),
  codex: s__('AiGovernance|Codex'),
};

// Action type badge variants shared by the Tool management tab and the Top tools card.
export const ACTION_TYPE_BADGE_VARIANTS = { READ: 'info', WRITE: 'warning', DESTROY: 'danger' };
