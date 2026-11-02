import { humanize } from '~/lib/utils/text_utility';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { formatAgentDefinition } from 'ee/ai/duo_agents_platform/utils';
import { formatSessionSource } from 'ee/ai/governance/utils';
import { CLIENT_TYPES, DEFAULT_CLIENT_TYPE } from './constants';

/**
 * Maps a `duoWorkflowSessionArtifacts` node onto the `aiGovernanceSessions`
 * shape, so components only handle one shape whichever API the flag selects.
 *
 * @param {Object} node - A DuoWorkflowSessionArtifact node.
 * @returns {Object}
 */
export function normalizeLegacySession(node) {
  return {
    ...node,
    flowType: node.workflowDefinition,
    sessionStartedAt: node.workflowCreatedAt,
    sessionId: String(getIdFromGraphQLId(node.id)),
  };
}

/**
 * Returns the display name of a session. External sessions can have no flow
 * type, so their source names them instead.
 *
 * @param {Object} item - A session item.
 * @returns {string}
 */
export function formatSessionName(item) {
  const sourceLabel = formatSessionSource(item);

  if (!item?.flowType && sourceLabel) {
    return sourceLabel;
  }

  return formatAgentDefinition(item?.flowType);
}

/**
 * Converts a snake_case audit event name into a human-readable title.
 *
 * Examples:
 *   'ai_agent_session_ended'   => 'Agent session ended'
 *   'ai_llm_input_sent'        => 'Llm input sent'
 *   'ai_tool_invoked'          => 'Tool invoked'
 *
 * @param {string} name - The raw event name from the API.
 * @returns {string}
 */
export function formatEventName(name) {
  if (!name) return '';
  return name
    .replace(/^ai_/, '')
    .replace(/_/g, ' ')
    .replace(/^./, (c) => c.toUpperCase());
}

/**
 * Returns the client type object for a session artifact item.
 *
 * `agentType` is null for sessions run on the GitLab Duo Agent Platform and a
 * raw value like `claude-code` for external agents. Unknown values are
 * humanised so the report never misattributes a session to GitLab Duo.
 *
 * @param {Object} item - A session artifact item.
 * @returns {{ name: string, icon?: string }}
 */
export function getClientType(item) {
  if (!item.agentType) {
    return DEFAULT_CLIENT_TYPE;
  }

  return CLIENT_TYPES[item.agentType] || { name: humanize(item.agentType, '-') };
}
