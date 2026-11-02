import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import { isScanProfileTypeVisible } from './scan_profiles/utils';

const isString = (value) => typeof value === 'string';
const isBoolean = (value) => typeof value === 'boolean';

export const isValidConfigurationEntity = (object) => {
  if (object == null) {
    return false;
  }

  const { field, type, description, label, value } = object;

  return (
    isString(field) &&
    isString(type) &&
    isString(description) &&
    isString(label) &&
    value !== undefined
  );
};

export const isValidAnalyzerEntity = (object) => {
  if (object == null) {
    return false;
  }

  const { name, label, enabled } = object;

  return isString(name) && isString(label) && isBoolean(enabled);
};

export const getAvailableScanProfiles = (data) =>
  (data?.group?.availableSecurityScanProfiles ?? []).filter(
    (profile) =>
      isScanProfileTypeVisible(profile.scanType) &&
      profile.scanType !== SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
  );
