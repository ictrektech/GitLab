import { s__ } from '~/locale';
import { resolveCatalogEntry } from './catalog/helpers';
import { ALL_TRIGGERS } from './catalog/triggers';
import {
  POLICY_VERDICT_ALLOW,
  POLICY_VERDICT_DENY,
  POLICY_VERDICT_REQUIRE_APPROVAL,
} from './constants';

export const WINDOW_DAYS = 7;

// The count documents cap the count at this and the server answers limit + 1
// past it: a group's evaluations are reached through its policies, one index
// scan per policy, so an exact count would grow with the group. The tile
// renders anything past the cap as "1,000+".
export const EVALUATIONS_COUNT_LIMIT = 1000;

/**
 * Start of the reporting window the evaluation stats cover.
 *
 * The window is WINDOW_DAYS calendar days in UTC, inclusive of today, so the
 * boundary is UTC midnight (WINDOW_DAYS - 1) days back and today counts as a
 * partial day.
 *
 * The boundary is pinned to UTC midnight rather than the current instant so
 * everyone reading the same organization on the same day sees the same number,
 * and so the value is a stable Apollo cache key instead of a fresh one on
 * every mount.
 *
 * @returns {String} ISO 8601 timestamp
 */
export const startOfReportingWindow = () => {
  const start = new Date();

  start.setUTCHours(0, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() - (WINDOW_DAYS - 1));

  return start.toISOString();
};

/**
 * Reads the total from a `policyEvaluations` connection: the exact count up to
 * EVALUATIONS_COUNT_LIMIT, one past it beyond.
 *
 * A null connection is a viewer who cannot read the container's policies, or
 * a container whose policy store experiment is off. Neither is a zero, so it
 * reads as unknown and the caller renders a placeholder rather than a number
 * nobody verified.
 *
 * For a group the count covers only that group's own policies, never an
 * ancestor's, which matches the list the stat sits above.
 *
 * @param {Object|null} connection
 * @returns {Number|null}
 */
export const toEvaluationsCount = (connection) => connection?.count ?? null;

// Page the detail page's evaluations list asks for. The resolver caps a page at 50, so
// this stays a request for the recent ones rather than the whole history.
export const EVALUATIONS_PAGE_SIZE = 20;

// GraphQL serves an enum as its value name — the wire id upcased, with dots replaced —
// so a trigger has to be mapped back before the catalog can resolve it. Mode and verdict
// need no map: their ids are the lowercased name.
const TRIGGER_IDS_BY_ENUM = new Map(
  ALL_TRIGGERS.map(({ id }) => [id.replace(/\./g, '_').toUpperCase(), id]),
);

const VERDICT = {
  [POLICY_VERDICT_ALLOW]: { label: s__('PolicyStore|Allowed'), variant: 'success' },
  [POLICY_VERDICT_DENY]: { label: s__('PolicyStore|Denied'), variant: 'danger' },
  [POLICY_VERDICT_REQUIRE_APPROVAL]: {
    label: s__('PolicyStore|Approval required'),
    variant: 'warning',
  },
};

export const verdictLabel = (verdict) => VERDICT[verdict]?.label || verdict;
export const verdictVariant = (verdict) => VERDICT[verdict]?.variant || 'neutral';

/**
 * Maps a `policyEvaluations` connection to the rows the policy detail page renders.
 *
 * A null connection is a viewer who cannot read the container's policies, or a container
 * whose policy store experiment is off. That is not an empty history, so it reads as
 * unknown and the caller says so rather than claiming the policy has never run — the
 * same line toEvaluationsCount draws for the stat tile.
 *
 * @param {Object|null} connection
 * @returns {Array|null} The rows, or null when the read produced no connection.
 */
export const toEvaluations = (connection) =>
  connection?.nodes?.map((node) => ({
    id: node.id,
    trigger: resolveCatalogEntry(
      ALL_TRIGGERS,
      TRIGGER_IDS_BY_ENUM.get(node.triggerType) ?? node.triggerType,
    ),
    mode: node.mode?.toLowerCase(),
    verdict: node.verdict?.toLowerCase(),
    projectId: node.projectId ?? null,
    project: node.project ?? null,
    evaluatedAt: node.evaluatedAt,
    violations: node.violations ?? [],
  })) ?? null;
