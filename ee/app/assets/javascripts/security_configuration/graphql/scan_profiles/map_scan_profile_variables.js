import {
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

// Scan profile configuration is stored per trigger, so there is nowhere to put a profile-level value.
// Until profile-level storage exists, fake it by writing the same configuration to every trigger that accepts one.

const CONFIGURATION_INPUT_KEYS = {
  [SCAN_PROFILE_TYPE_SAST]: 'sast',
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: 'secretDetection',
  [SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING]: 'dependencyScanning',
};

// Mirrors UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE in ee/app/models/security/scan_profile_trigger.rb
const UNCONFIGURABLE_TRIGGER_TYPES = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: ['GIT_PUSH_EVENT'],
};

export const isTriggerConfigurable = (scanType, triggerType) =>
  Boolean(CONFIGURATION_INPUT_KEYS[scanType]) &&
  !(UNCONFIGURABLE_TRIGGER_TYPES[scanType] ?? []).includes(triggerType);

// GraphQL enums are always sent and received by the *name* declared on the enum type (e.g. `FIPS`),
// never by the value the backend resolves them to (e.g. `-fips`, the literal written to the CI
// variable). variable_definitions.js keeps that backend-facing value as the canonical one, since
// it's what defaults/comparisons/dropdown options reason about, so translate only here, at the
// GraphQL boundary. Mirrors Types::Security::ScanProfiles::ImageSuffixEnum,
// Types::Security::ScanProfiles::AdvancedSastPartialScanEnum,
// Types::Security::ScanProfiles::SecureLogLevelEnum and
// Types::Security::ScanProfiles::DependencyResolutionJobEnum.
const ENUM_VALUE_TO_NAME = {
  // eslint-disable-next-line @gitlab/require-i18n-strings -- GraphQL enum names/backend values, not prose
  imageSuffix: { '': 'DEFAULT', '-fips': 'FIPS' },
  advancedSastPartialScan: { differential: 'DIFFERENTIAL', false: 'DISABLED' },
  secureLogLevel: { fatal: 'FATAL', error: 'ERROR', warn: 'WARN', info: 'INFO', debug: 'DEBUG' },
  disabledResolutionJobs: { maven: 'MAVEN', gradle: 'GRADLE', python: 'PYTHON' },
};

const ENUM_NAME_TO_VALUE = Object.fromEntries(
  Object.entries(ENUM_VALUE_TO_NAME).map(([field, valueToName]) => [
    field,
    Object.fromEntries(Object.entries(valueToName).map(([value, name]) => [name, value])),
  ]),
);

const translateEnum = (mapping, value) => mapping?.[value] ?? value;

const translateEnums = (configuration, mapping) =>
  Object.fromEntries(
    Object.entries(configuration).map(([key, value]) => [
      key,
      Array.isArray(value)
        ? value.map((item) => translateEnum(mapping[key], item))
        : translateEnum(mapping[key], value),
    ]),
  );

const GRAPHQL_INTEGER_FIELDS = ['maxDepth', 'apiTimeout', 'apiScanDownloadDelay'];

export const isIntegerValue = (value) => /^-?\d+$/.test(String(value));

const castIntegers = (configuration) =>
  Object.fromEntries(
    Object.entries(configuration)
      .filter(([key, value]) => !(GRAPHQL_INTEGER_FIELDS.includes(key) && value === ''))
      .map(([key, value]) => [
        key,
        GRAPHQL_INTEGER_FIELDS.includes(key) && isIntegerValue(value) ? Number(value) : value,
      ]),
  );

/**
 * Translates the enum fields of each trigger's configuration from the GraphQL *name* (e.g.
 * `DEFAULT`) back to the canonical backend value (e.g. `''`) variable_definitions.js and its
 * option lists key on. Needed by any read-only view that renders a profile's `triggerSettings`
 * straight from a GraphQL query, since readScanProfileTriggers only covers the edit form's shape.
 *
 * @param {Object[]} [triggerSettings] One `{ triggerType, configuration }` per trigger, as
 *   returned by the scan profile GraphQL query.
 * @returns {Object[]} Same shape, with enum fields in `configuration` translated to their value.
 */
export const translateTriggerSettingsFromGraphql = (triggerSettings = []) =>
  triggerSettings.map((triggerSetting) => ({
    ...triggerSetting,
    configuration: triggerSetting.configuration
      ? translateEnums(triggerSetting.configuration, ENUM_NAME_TO_VALUE)
      : triggerSetting.configuration,
  }));

/**
 * Builds the `triggers` input for the `securityScanProfileCreate` and
 * `securityScanProfileUpdate` mutations.
 *
 * @param {string} scanType Scan type of the profile.
 * @param {string[]} [enabledTriggers] Full desired set of trigger types; any type left out is
 *   destroyed by the mutation rather than disabled.
 * @param {Object} [profileConfiguration] Values applied to every configurable trigger.
 * @param {Object} [triggerConfigurations] Values keyed by trigger type; these win key by key over
 *   the matching `profileConfiguration` ones.
 * @returns {Object[]} One entry per enabled trigger, bare where no configuration applies.
 */
export const mapScanProfileVariables = ({
  scanType,
  enabledTriggers = [],
  profileConfiguration,
  triggerConfigurations = {},
}) => {
  const configurationKey = CONFIGURATION_INPUT_KEYS[scanType];

  return enabledTriggers.map((triggerType) => {
    if (!isTriggerConfigurable(scanType, triggerType)) {
      return { triggerType };
    }

    const configuration = { ...profileConfiguration, ...triggerConfigurations[triggerType] };

    if (!Object.keys(configuration).length) {
      return { triggerType };
    }

    return {
      triggerType,
      configuration: {
        [configurationKey]: castIntegers(translateEnums(configuration, ENUM_VALUE_TO_NAME)),
      },
    };
  });
};

export const buildScanProfileUpdateInput = ({
  profileId,
  scanType,
  enabledTriggers,
  profileConfiguration,
  triggerConfigurations,
  stripDefaults = false,
}) => ({
  id: profileId,
  stripDefaults,
  triggers: mapScanProfileVariables({
    scanType,
    enabledTriggers,
    profileConfiguration,
    triggerConfigurations,
  }),
});

export const buildScanProfileCreateInput = ({
  namespaceId,
  scanType,
  name,
  description,
  enabledTriggers,
  profileConfiguration,
  triggerConfigurations,
  stripDefaults = false,
}) => ({
  namespaceId,
  scanType,
  name,
  description,
  stripDefaults,
  triggers: mapScanProfileVariables({
    scanType,
    enabledTriggers,
    profileConfiguration,
    triggerConfigurations,
  }),
});

export const readScanProfileTriggers = (triggerSettings = []) => ({
  enabledTriggers: triggerSettings.map(({ triggerType }) => triggerType),
  triggerConfigurations: Object.fromEntries(
    triggerSettings
      .map(({ triggerType, configuration }) => [
        triggerType,
        translateEnums(
          Object.fromEntries(
            Object.entries(configuration ?? {}).filter(
              ([key, value]) => key !== '__typename' && value !== null,
            ),
          ),
          ENUM_NAME_TO_VALUE,
        ),
      ])
      .filter(([, values]) => Object.keys(values).length),
  ),
});
