import { s__ } from '~/locale';

export const NAMESPACE_GROUP = 'group';
export const NAMESPACE_PROJECT = 'project';

// Matches the real backend wire values (Security::DependencyFirewallPolicyRule#mode).
export const MODE_ENFORCE = 'ENFORCE';
export const MODE_WARN = 'WARN';

// Matches the SecurityPolicyRelationType GraphQL enum wire value.
export const SOURCE_RELATIONSHIP_DESCENDANT = 'DESCENDANT';

export const ICON_BLOCKED = 'status-failed';
export const ICON_WARNED = 'status-alert';

export const ICON_VARIANT_TEXT_CLASSES = {
  danger: 'gl-text-danger',
  warning: 'gl-text-warning',
};

// Matches the VulnerabilitySeverity GraphQL enum wire values (uppercase).
export const SEVERITY_ICONS = {
  CRITICAL: 'severity-critical',
  HIGH: 'severity-high',
};

export const TIME_WINDOW_7_DAYS = 7;
export const TIME_WINDOW_30_DAYS = 30;
export const DEFAULT_TIME_WINDOW_DAYS = TIME_WINDOW_30_DAYS;

export const TIME_WINDOW_OPTIONS = [
  { value: TIME_WINDOW_7_DAYS, text: s__('DependencyFirewall|Last 7 days') },
  { value: TIME_WINDOW_30_DAYS, text: s__('DependencyFirewall|Last 30 days') },
];
