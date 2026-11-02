import { n__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import { AGENT_STEP_PILL_VARIANTS, READINESS_SCORE_MIN, READINESS_SCORE_MAX } from './constants';

export const getVariantColor = (variant) =>
  AGENT_STEP_PILL_VARIANTS[variant] ?? AGENT_STEP_PILL_VARIANTS.placeholder;

export const getAwaitingInputLabel = (count) =>
  sprintf(
    n__(
      'AgentPlan|Awaiting input (%{count} question)',
      'AgentPlan|Awaiting input (%{count} questions)',
      count,
    ),
    { count },
  );

export const isValidReadinessScore = (score) =>
  score === null ||
  (Number.isInteger(score) && score >= READINESS_SCORE_MIN && score <= READINESS_SCORE_MAX);

export const trackWorkplanImplement = (surface, readinessScore) => {
  InternalEvents.trackEvent('click_work_item_workplan_implement', {
    property: surface,
    ...(Number.isFinite(readinessScore) && { value: readinessScore }),
  });
};
