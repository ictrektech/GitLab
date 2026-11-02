import { s__ } from '~/locale';

export const SEVERITY_LOW = 'LOW';
export const SEVERITY_MEDIUM = 'MEDIUM';
export const SEVERITY_HIGH = 'HIGH';
export const SEVERITY_CRITICAL = 'CRITICAL';

// Severity order, lowest first. The meter fills one segment per rung up to and
// including the current level, so the index here also drives how many are filled.
export const SEVERITY_ORDER = [SEVERITY_LOW, SEVERITY_MEDIUM, SEVERITY_HIGH, SEVERITY_CRITICAL];

// Classes for the meter's filled segments, climbing with severity. They back onto
// the status icon-colour tokens (see components/severity_meter.scss) so the fills
// read clearly against the neutral track.
export const SEVERITY_METER_FILL = {
  [SEVERITY_LOW]: 'severity-meter-fill-low',
  [SEVERITY_MEDIUM]: 'severity-meter-fill-medium',
  [SEVERITY_HIGH]: 'severity-meter-fill-high',
  [SEVERITY_CRITICAL]: 'severity-meter-fill-critical',
};

export const SEVERITY_LABELS = {
  [SEVERITY_LOW]: s__('SeverityMeter|Low'),
  [SEVERITY_MEDIUM]: s__('SeverityMeter|Medium'),
  [SEVERITY_HIGH]: s__('SeverityMeter|High'),
  [SEVERITY_CRITICAL]: s__('SeverityMeter|Critical'),
};
