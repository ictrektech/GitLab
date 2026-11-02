// Mirrors the limits in ee/app/models/work_items/decision.rb, so the form fails before the
// request does. The decision text is saved as an option, so it takes the option content limit
// from ee/app/models/work_items/decision_option.rb. An unresolved decision keeps it on the
// question.
export const DECISION_TEXT_LENGTH_MAX = 500;
export const DECISION_TITLE_LENGTH_MAX = 255;
export const DECISION_DESCRIPTION_LENGTH_MAX = 1000;
export const DECISION_RATIONALE_LENGTH_MAX = 800;

// How close to a limit a field has to be before the count is worth showing. Below this the
// count is noise on a form where most entries are nowhere near the limit.
export const DECISION_REMAINING_COUNT_THRESHOLD = 50;

// The card owns the anchor and the panel clears it on close, so both sides read the prefix
// from here.
export const DECISION_ANCHOR_PREFIX = 'decision_';

// Mirrors the `WorkItemDecisionState` GraphQL enum. The state is derived from the timestamps on
// the record, so an archived decision is always a resolved one too.
export const DECISION_STATE_ARCHIVED = 'ARCHIVED';
// The enum calls an open, unresolved decision `ACTIVE`.
export const DECISION_STATE_OPEN = 'ACTIVE';
