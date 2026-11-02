import { s__ } from '~/locale';

export const RULE_TYPE_LICENSE = 'license';
export const RULE_TYPE_MALICIOUS = 'malicious';
export const RULE_TYPE_RISK_SEVERITY = 'risk_severity';
export const RULE_TYPE_PACKAGE_VERSION = 'package_version';
export const PACKAGE_VERSION_REASON_MAX_LENGTH = 20;
export const PACKAGE_VERSION_LINK_MAX_LENGTH = 2048;

export const SEVERITY_LISTBOX_ITEMS = [
  { value: 'critical', text: s__('SecurityOrchestration|Critical') },
  { value: 'high', text: s__('SecurityOrchestration|High') },
  { value: 'medium', text: s__('SecurityOrchestration|Medium') },
  { value: 'low', text: s__('SecurityOrchestration|Low') },
  { value: 'info', text: s__('SecurityOrchestration|Info') },
  { value: 'unknown', text: s__('SecurityOrchestration|Unknown') },
];

// Matches the backend's risk_severity JSON schema enum exactly (critical/high/medium/low
// only), rather than excluding info/unknown, so a future SEVERITY_LISTBOX_ITEMS addition
// can't silently become a schema-invalid option here.
export const RISK_SEVERITY_LISTBOX_ITEMS = SEVERITY_LISTBOX_ITEMS.filter(({ value }) =>
  ['critical', 'high', 'medium', 'low'].includes(value),
);

export const DEFAULT_RISK_SEVERITY_THRESHOLD = 0;

export const ENFORCEMENT_ENFORCED = 'enforced';
export const ENFORCEMENT_WARN = 'warn';

// Descriptions for the Warn/Enforce segmented control in the policy details card.
export const ENFORCEMENT_MODE_DESCRIPTIONS = {
  [ENFORCEMENT_WARN]: s__(
    'SecurityOrchestration|Records what would have been blocked without failing the build. The request is allowed and a warned audit event is recorded. Applies to every rule in this policy.',
  ),
  [ENFORCEMENT_ENFORCED]: s__(
    'SecurityOrchestration|Blocks the download or build when a violation is detected. The request is denied and a blocked audit event is recorded. Applies to every rule in this policy.',
  ),
};

// Every rule card ends with the same "Except these packages" field; the vulnerability
// variant appears only on the known-vulnerabilities card.
export const EXCEPT_PACKAGES_FIELD = {
  label: s__('SecurityOrchestration|Except these packages'),
  placeholder: 'pkg:npm/my-internal-lib',
  hint: s__(
    'SecurityOrchestration|One package URL per entry. Omit the version to except every version of the package.',
  ),
};

export const EXCEPT_VULNERABILITIES_FIELD = {
  label: s__('SecurityOrchestration|Except these vulnerabilities'),
  placeholder: 'CVE-2024-12345',
  hint: s__(
    'SecurityOrchestration|One vulnerability identifier per entry, as it appears in the advisory database.',
  ),
};
