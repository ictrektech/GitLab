import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { DECISION_ANCHOR_PREFIX, DECISION_STATE_ARCHIVED, DECISION_STATE_OPEN } from './constants';

/**
 * The URL hash that points at a decision card.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {string} The anchor, for example `decision_12`.
 */
export const decisionAnchorId = (decision) =>
  `${DECISION_ANCHOR_PREFIX}${getIdFromGraphQLId(decision.id)}`;

/**
 * The decisions that have been archived.
 *
 * @param {Array<Object>} decisions Decisions from the decision log query.
 * @returns {Array<Object>} The decisions whose state is archived.
 */
export const getArchivedDecisions = (decisions = []) =>
  decisions.filter((decision) => decision.state === DECISION_STATE_ARCHIVED);

/**
 * The decisions that have been resolved, archived ones included, which are the ones the log shows.
 *
 * GitLab Duo opens a decision for each question it posts, but the log has no way yet to tell an
 * open decision apart from a resolved one. Remove this once that UX is decided in
 * https://gitlab.com/gitlab-org/gitlab/-/work_items/631883.
 *
 * @param {Array<Object>} decisions Decisions from the decision log query.
 * @returns {Array<Object>} The decisions whose state is not open.
 */
export const resolvedDecisions = (decisions = []) =>
  decisions.filter((decision) => decision.state !== DECISION_STATE_OPEN);

/**
 * The decisions a work item currently stands on.
 *
 * An archived decision stays on the record, but it no longer counts as something the work item has
 * settled. The header button, the panel heading and the list all read the same set, so a reader
 * never sees a count that disagrees with what is on screen.
 *
 * Non-archived decisions are always active, regardless of any other status they may carry in the
 * future. Deriving active from "not archived" is therefore more robust than the inverse.
 *
 * @param {Array<Object>} decisions Decisions from the decision log query.
 * @returns {Array<Object>} The decisions that are not archived.
 */
export const activeDecisions = (decisions = []) =>
  decisions.filter((decision) => decision.state !== DECISION_STATE_ARCHIVED);

/**
 * The options a decision settled on. Only a selected option counts as settled.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {Array<Object>} The settled options, in the order they were fetched.
 */
export const settledDecisionOptions = (decision) =>
  (decision?.options?.nodes || []).filter((option) => option.selected);

/**
 * The decision itself, as the card heads it and the edit form shows it.
 *
 * A decision can settle on more than one option, so they are joined into one text. Saving an edit
 * replaces them with a single option that holds the new text. With no settled option, the question
 * stands in for it.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {string} The decision text, or an empty string when there is none.
 */
export const decisionText = (decision) =>
  settledDecisionOptions(decision)
    .map(({ content }) => content)
    .join(', ') ||
  decision?.question ||
  decision?.title ||
  '';

/**
 * The one link a decision points at.
 *
 * A decision recorded by hand carries the link its author gave. One resolved from a thread carries
 * the comment that settled it, which the author cannot change.
 *
 * @param {Object} decision A decision from the decision log query.
 * @returns {string} The link, or an empty string when there is none.
 */
export const decisionSourceUrl = (decision) => decision?.sourceLink || decision?.noteUrl || '';
