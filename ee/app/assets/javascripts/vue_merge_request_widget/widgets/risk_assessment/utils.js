import { s__, sprintf } from '~/locale';
import {
  CONFIDENCE_LOW,
  DEFAULT_RISK_ASSESSMENT,
  IN_PROGRESS_STATUSES,
  STATUS_COMPLETE,
  STATUS_FAILED,
  STATUS_PENDING,
  TIER_LABELS,
  riskHeadline,
} from './constants';

/**
 * What a risk assessment shows, shared by the merge request widget and the
 * merge request overview so the two cannot drift apart.
 *
 * @param {Object|null} riskAssessment The GraphQL risk assessment, or null before it arrives.
 * @param {Object} options
 * @param {Boolean} options.isLoading Whether the assessment query is in flight.
 * @param {Boolean} options.duoChatAvailable Whether the user can open the Duo session.
 */
export const getRiskAssessmentState = (
  riskAssessment,
  { isLoading = false, duoChatAvailable = false } = {},
) => {
  const assessment = { ...DEFAULT_RISK_ASSESSMENT, ...riskAssessment };
  const {
    status,
    riskTier: tier,
    confidenceTier,
    rationale,
    stale: isStale,
    duoWorkflowId,
    contributingSignals: contributions,
  } = assessment;
  const isLowConfidence = confidenceTier === CONFIDENCE_LOW;
  // A key matching neither a registered signal nor a claim domain comes back with
  // a null label. Naming it as a raw key reads worse than leaving it out.
  const missingSignalLabels = assessment.missingSignals.map(({ label }) => label).filter(Boolean);

  // A refresh leaves the previous score in place for the scoring job to replace,
  // so a queued record still carries a result worth showing. A failed run is a
  // hard stop instead: there is no result left to trust.
  const isAssessed = [STATUS_COMPLETE, ...IN_PROGRESS_STATUSES].includes(status) && Boolean(tier);
  const isRefreshing = isAssessed && IN_PROGRESS_STATUSES.includes(status);
  const showsStaleWarning = isStale && !isRefreshing && (isAssessed || status === STATUS_FAILED);
  const hasDetails =
    isAssessed &&
    !isRefreshing &&
    Boolean(rationale || contributions.length || (isLowConfidence && missingSignalLabels.length));
  const showsSessionLink = Boolean(duoWorkflowId) && duoChatAvailable && hasDetails;
  const tierLabel = TIER_LABELS[tier] ?? tier;

  let meterLabel;
  if (isLoading) {
    meterLabel = s__('RiskAssessment|Assessing risk');
  } else if (tier) {
    // Risk-domain wording for the meter's accessible name, e.g. "Risk level: High risk".
    meterLabel = sprintf(s__('RiskAssessment|Risk level: %{level}'), { level: tierLabel });
  } else {
    meterLabel = s__('RiskAssessment|Risk level not available');
  }

  let summaryTitle;
  if (isAssessed) {
    summaryTitle = riskHeadline(tier, confidenceTier);
  } else if (isLoading) {
    summaryTitle = s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Evaluating…');
  } else if (status === STATUS_FAILED) {
    summaryTitle = s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Unavailable');
  } else if (IN_PROGRESS_STATUSES.includes(status)) {
    summaryTitle = s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Queued');
  } else if (status === STATUS_PENDING) {
    summaryTitle = s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Pending');
  } else {
    summaryTitle = s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Not available');
  }

  return {
    status,
    tier,
    tierLabel,
    confidenceTier,
    isLowConfidence,
    rationale,
    isStale,
    duoWorkflowId,
    contributions,
    missingSignalLabels,
    isAssessed,
    isRefreshing,
    showsStaleWarning,
    hasDetails,
    showsSessionLink,
    showsFooter: showsStaleWarning || showsSessionLink,
    meterSeverity: isAssessed ? tier : null,
    meterLabel,
    summaryTitle,
  };
};
