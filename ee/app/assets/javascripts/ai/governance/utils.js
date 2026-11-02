import { nDaysBefore, toISODateFormat } from '~/lib/utils/datetime_utility';
import { humanize } from '~/lib/utils/text_utility';
import { objectToQuery } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import {
  AGENT_CLASS_ALL,
  AGENT_TYPE_LABELS,
  SESSION_SOURCE_LABELS,
  TIMEFRAME_LAST_SEVEN_DAYS,
  TIMEFRAME_LAST_THIRTY_DAYS,
} from './constants';

const TIMEFRAME_DAYS = {
  [TIMEFRAME_LAST_SEVEN_DAYS]: 7,
  [TIMEFRAME_LAST_THIRTY_DAYS]: 30,
};

/**
 * Returns the product name of an external agent type, such as `claude-code`.
 *
 * @param {string} agentType - The `agent_type` the backend stores.
 * @returns {string}
 */
export function formatAgentType(agentType) {
  return AGENT_TYPE_LABELS[agentType] || humanize(agentType, '-');
}

/**
 * Returns the label of a session's source, or undefined for an unknown source.
 *
 * glab records every session with the `CLAUDE_CODE_GLAB` source, whichever agent
 * ran it, so a glab session is named after its agent type instead.
 *
 * @param {Object} session - A session with `source` and `agentType`.
 * @returns {string|undefined}
 */
export function formatSessionSource(session) {
  const { source, agentType } = session || {};

  if (source === 'CLAUDE_CODE_GLAB' && agentType) {
    return sprintf(s__('AiGovernance|%{agent} (glab)'), {
      agent: formatAgentType(agentType),
    });
  }

  return SESSION_SOURCE_LABELS[source];
}

/**
 * Returns a link to the Audit events tab with the given filters, limited to the
 * dashboard's timeframe and agent class so the tab lists the sessions a card counted.
 *
 * The window starts at the beginning of the UTC day, as the backend's
 * `Ai::Governance::MetricsTimeframe` does, and runs up to now.
 *
 * @param {string} timeframe - An `AiGovernanceMetricsTimeframe` value.
 * @param {Object} filters - Audit events filter tokens, keyed by token type.
 *   An `agentClass` of `ALL` is left out, since the tab shows every class by default.
 * @returns {string}
 */
export function auditEventsHref(timeframe, { agentClass, ...filters } = {}) {
  const params = { tab: 'agent-artifacts', ...filters };
  const days = TIMEFRAME_DAYS[timeframe];

  if (agentClass && agentClass !== AGENT_CLASS_ALL) {
    params.agentClass = agentClass;
  }

  if (days) {
    params.startTimeAfter = toISODateFormat(nDaysBefore(new Date(), days, { utc: true }), true);
  }

  return `?${objectToQuery(params)}`;
}
