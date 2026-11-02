import { s__ } from '~/locale';

export const PRODUCTS = {
  duo_agent_platform: s__('SuperSonics|Duo Agent Platform'),
  secrets_manager: s__('SuperSonics|Secrets Manager'),
  orbit: s__('SuperSonics|Orbit'),
  artifact_registry: s__('SuperSonics|Artifact Registry'),
  hosted_runners: s__('SuperSonics|Hosted Runners'),
};

export const FLOW_TYPES = {
  agentic_chat: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Agentic Chat') },
  ai_catalog_agent: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|AI Catalog based Agent or Flow'),
  },
  ai_gateway_proxy_use: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|AI Gateway Proxy'),
  },
  ambient: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Ambient Flow') },
  analytics_agent: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Analytics Agent'),
  },
  business_context_security_guidelines: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Business Context Security Guidelines'),
  },
  chat: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Agentic Chat') },
  ci_expert_agent: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|CI Expert Agent'),
  },
  code_review: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Code Review Flow') },
  code_suggestions: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Code Suggestions'),
  },
  convert_to_gitlab_ci: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Convert to GitLab CI/CD Flow'),
  },
  convert_to_gl_ci: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Convert to GitLab CI/CD Flow'),
  },
  dap_feature_legacy: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|DAP Feature (Legacy)'),
  },
  developer: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Developer Flow') },
  duo_chat_classic: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Duo Chat (Classic)'),
  },
  duo_permissions_assistant: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Duo Permissions Assistant'),
  },
  duo_planner: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Duo Planner') },
  fix_pipeline: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Fix Pipeline Flow'),
  },
  flow_creator: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Custom Flows') },
  gitlab_duo_mention_assistant: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|GitLab Duo Interactions in Merge Requests'),
  },
  issue_to_merge_request: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Issue to Merge Request Flow'),
  },
  onboarding_guide: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Onboarding Guide'),
  },
  orbit_agent: { product: PRODUCTS.duo_agent_platform, title: s__('SuperSonics|Orbit Agent') },
  recommend_reviewers: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Intelligent Reviewer Assignment'),
  },
  resolve_dependency_bump: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Dependency Bump Resolution Flow'),
  },
  resolve_sast_vulnerability: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|SAST Vulnerability Resolution Flow'),
  },
  sast_fp_detection: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|SAST FP Detection Flow'),
  },
  secrets_fp_detection: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Secrets FP Detection'),
  },
  security_analyst_agent: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Security Analyst Agent'),
  },
  security_review: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Security Review Flow'),
  },
  slack_assistant: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Slack Assistant'),
  },
  software_development: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Software Development Flow'),
  },
  support_assistant: {
    product: PRODUCTS.duo_agent_platform,
    title: s__('SuperSonics|Support Assistant'),
  },

  secrets_read: { product: PRODUCTS.secrets_manager, title: s__('SuperSonics|Secrets Read') },
  secrets_stored: { product: PRODUCTS.secrets_manager, title: s__('SuperSonics|Secrets Stored') },

  orbit_code_intelligence: { product: PRODUCTS.orbit, title: s__('SuperSonics|Code Intelligence') },
  orbit_core: { product: PRODUCTS.orbit, title: s__('SuperSonics|Core') },
  orbit_dws: { product: PRODUCTS.orbit, title: s__('SuperSonics|Duo Agent Platform') },
  orbit_frontend: { product: PRODUCTS.orbit, title: s__('SuperSonics|Frontend') },
  orbit_mcp: { product: PRODUCTS.orbit, title: s__('SuperSonics|MCP') },
  orbit_rest: { product: PRODUCTS.orbit, title: s__('SuperSonics|REST') },

  artifact_registry_component: {
    product: PRODUCTS.artifact_registry,
    title: s__('SuperSonics|Artifact Registry Components'),
  },
  artifact_registry_egress: {
    product: PRODUCTS.artifact_registry,
    title: s__('SuperSonics|Artifact Registry Egress'),
  },
  artifact_registry_storage: {
    product: PRODUCTS.artifact_registry,
    title: s__('SuperSonics|Artifact Registry Storage'),
  },

  runner_compute_usage: {
    product: PRODUCTS.hosted_runners,
    title: s__('SuperSonics|Runner Compute Usage'),
  },
};

export const QUANTITY_KIND_SNAPSHOT = 'snapshot';

export const NO_DATA_RANGE_LIMIT = 5;

export const EXPORTED_ALERT_ID = 'billable-usage-report-exported';
