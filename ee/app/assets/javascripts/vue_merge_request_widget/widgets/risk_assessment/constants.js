import { s__ } from '~/locale';
import { EXTENSION_ICONS } from '~/vue_merge_request_widget/constants';

export const RISK_CLASSIFICATION_FLOW_REFERENCE = 'risk_classification/v1';

// Wire values are StatusEnum's (state_machine names upcased by GraphQL), not
// RiskAssessment#status_name. QUEUED and PENDING both mean "not assessed yet".
export const STATUS_PENDING = 'PENDING';
export const STATUS_QUEUED = 'QUEUED';
export const STATUS_SCORING = 'SCORING';
export const STATUS_COMPLETE = 'COMPLETE';
export const STATUS_FAILED = 'FAILED';

// SCORING only tells the backend that the session already submitted, so the UI shows it as QUEUED.
export const IN_PROGRESS_STATUSES = [STATUS_QUEUED, STATUS_SCORING];

// The meter, not an icon, is the user-facing status here; this map only feeds
// mr-widget's expand telemetry so the risk lifecycle stays visible in metrics.
export const STATUS_ICONS = {
  [STATUS_PENDING]: EXTENSION_ICONS.neutral,
  [STATUS_QUEUED]: EXTENSION_ICONS.notice,
  [STATUS_SCORING]: EXTENSION_ICONS.notice,
  [STATUS_COMPLETE]: EXTENSION_ICONS.success,
  [STATUS_FAILED]: EXTENSION_ICONS.failed,
};

export const TIER_LOW = 'LOW';
export const TIER_MEDIUM = 'MEDIUM';
export const TIER_HIGH = 'HIGH';
export const TIER_CRITICAL = 'CRITICAL';

export const TIER_LABELS = {
  [TIER_LOW]: s__('RiskAssessment|Low risk'),
  [TIER_MEDIUM]: s__('RiskAssessment|Medium risk'),
  [TIER_HIGH]: s__('RiskAssessment|High risk'),
  [TIER_CRITICAL]: s__('RiskAssessment|Critical risk'),
};

export const CONFIDENCE_LOW = 'LOW';
export const CONFIDENCE_MEDIUM = 'MEDIUM';
export const CONFIDENCE_HIGH = 'HIGH';
export const CONFIDENCE_VERY_HIGH = 'VERY_HIGH';

// Each risk/confidence pair is its own fully-composed sentence rather than a frame
// with %{tier}/%{confidence} words substituted in. Splitting a sentence into
// independently-translated fragments cannot guarantee grammatical agreement (gender,
// case, word order) across languages, so translators get the whole sentence per
// state and control its structure. Keyed by `${riskTier}_${confidenceTier}`; the
// bold "Risk assessment:" prefix stays inside each string via %{boldStart}/%{boldEnd}.
const HEADLINES = {
  [`${TIER_LOW}_${CONFIDENCE_LOW}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Low with low confidence',
  ),
  [`${TIER_LOW}_${CONFIDENCE_MEDIUM}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Low with medium confidence',
  ),
  [`${TIER_LOW}_${CONFIDENCE_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Low with high confidence',
  ),
  [`${TIER_LOW}_${CONFIDENCE_VERY_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Low with very high confidence',
  ),
  [`${TIER_MEDIUM}_${CONFIDENCE_LOW}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Medium with low confidence',
  ),
  [`${TIER_MEDIUM}_${CONFIDENCE_MEDIUM}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Medium with medium confidence',
  ),
  [`${TIER_MEDIUM}_${CONFIDENCE_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Medium with high confidence',
  ),
  [`${TIER_MEDIUM}_${CONFIDENCE_VERY_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Medium with very high confidence',
  ),
  [`${TIER_HIGH}_${CONFIDENCE_LOW}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} High with low confidence',
  ),
  [`${TIER_HIGH}_${CONFIDENCE_MEDIUM}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} High with medium confidence',
  ),
  [`${TIER_HIGH}_${CONFIDENCE_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} High with high confidence',
  ),
  [`${TIER_HIGH}_${CONFIDENCE_VERY_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} High with very high confidence',
  ),
  [`${TIER_CRITICAL}_${CONFIDENCE_LOW}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Critical with low confidence',
  ),
  [`${TIER_CRITICAL}_${CONFIDENCE_MEDIUM}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Critical with medium confidence',
  ),
  [`${TIER_CRITICAL}_${CONFIDENCE_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Critical with high confidence',
  ),
  [`${TIER_CRITICAL}_${CONFIDENCE_VERY_HIGH}`]: s__(
    'RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Critical with very high confidence',
  ),
};

// Fallback for a completed record whose confidence didn't resolve (the backend
// scores tier and confidence independently, so confidence can be nil while tier
// is set). One fully-composed sentence per tier, keeping the bold prefix so this
// state matches every other headline rather than rendering a bare tier word.
const HEADLINES_TIER_ONLY = {
  [TIER_LOW]: s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Low'),
  [TIER_MEDIUM]: s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Medium'),
  [TIER_HIGH]: s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} High'),
  [TIER_CRITICAL]: s__('RiskAssessment|%{boldStart}Risk assessment:%{boldEnd} Critical'),
};

export const riskHeadline = (riskTier, confidenceTier) => {
  // Last resort surfaces the raw enum for an unrecognized tier; HEADLINES_TIER_ONLY
  // already covers every known tier, so a humanized-label lookup here would be dead.
  return HEADLINES[`${riskTier}_${confidenceTier}`] ?? HEADLINES_TIER_ONLY[riskTier] ?? riskTier;
};

// Bands for a signal's absolute contribution, in points on the 0-100 risk score.
// They follow the backend's v1 weights, which are not calibrated yet.
export const CONTRIBUTION_MAJOR_THRESHOLD = 10;
export const CONTRIBUTION_MINOR_THRESHOLD = 4;

// Correction row the scoring function adds when mitigations exceed their cap.
// Must match MITIGATION_CAP_SIGNAL in ee/lib/gitlab/duo/risk_assessment/scoring_function/v1.rb.
export const MITIGATION_CAP_SIGNAL = 'mitigation_cap';

// The widget mounts while the query is still in flight, so it needs every field
// present before the assessment arrives.
export const DEFAULT_RISK_ASSESSMENT = {
  status: null,
  riskTier: null,
  confidenceTier: null,
  rationale: null,
  stale: false,
  duoWorkflowId: null,
  contributingSignals: [],
  missingSignals: [],
};
