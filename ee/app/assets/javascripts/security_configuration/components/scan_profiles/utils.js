import { isEqual } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import {
  BOOLEAN_OPTIONS,
  SCAN_PROFILE_CATEGORIES,
  SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_PROFILE_TYPE_SKILLGUARD,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
  SCAN_TRIGGER_DEFINITIONS,
  SCAN_TRIGGER_DEFINITION_OVERRIDES,
} from '~/security_configuration/constants';
import {
  isIntegerValue,
  translateTriggerSettingsFromGraphql,
} from 'ee/security_configuration/graphql/scan_profiles/map_scan_profile_variables';
import {
  variableDefinitionsFor,
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
} from './variable_definitions';

// Mirrors the trigger types accepted per scan type by the backend enum
// (see ee/app/models/concerns/enums/security.rb / scan_profile_trigger.rb).
const ALLOWED_TRIGGER_TYPES_BY_SCAN_TYPE = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: [
    'MERGE_REQUEST_PIPELINE',
    'DEFAULT_BRANCH_PIPELINE',
    'GIT_PUSH_EVENT',
  ],
  [SCAN_PROFILE_TYPE_SAST]: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
  [SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING]: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
  [SCAN_PROFILE_TYPE_BUSINESS_LOGIC]: ['MERGE_REQUEST_PIPELINE'],
  [SCAN_PROFILE_TYPE_SKILLGUARD]: ['MERGE_REQUEST_PIPELINE'],
};

// Every triage preset is GitLab-recommended, so name the default.
const DEFAULT_PROFILE_NAME_BY_SCAN_TYPE = {
  // eslint-disable-next-line @gitlab/require-i18n-strings
  [SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION]: 'Triage and Remediation (Standard)',
};

export const scanTypeName = (scanType) => SCAN_PROFILE_CATEGORIES[scanType]?.name || scanType;

export const scanTypeHelpLink = (scanType) => SCAN_PROFILE_CATEGORIES[scanType]?.helpLink;

export const isScanProfileTypeVisible = (scanType) => {
  if (!SCAN_PROFILE_CATEGORIES[scanType]) return false;
  if (scanType === SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION) {
    return Boolean(window.gon?.features?.triageAndRemediationProfilesUi);
  }
  return true;
};

// Lowercases the name for mid-sentence use, unless it's already an all-caps acronym (e.g.
// "SAST" stays as-is, but "Secret detection" becomes "secret detection").
export const scanTypeSentenceCase = (scanType) => {
  const name = scanTypeName(scanType);
  return name === name.toUpperCase() ? name : name.charAt(0).toLowerCase() + name.slice(1);
};

export const allowedTriggersFor = (scanType) => ALLOWED_TRIGGER_TYPES_BY_SCAN_TYPE[scanType] ?? [];

export const isPushProtectionTrigger = ({ triggerType }) => triggerType === 'GIT_PUSH_EVENT';

export const resolveTriggers = (triggers = [], scanType) => {
  const enabledTriggerTypes = new Set(triggers);

  return allowedTriggersFor(scanType)
    .filter(
      (triggerType) =>
        enabledTriggerTypes.has(triggerType) && SCAN_TRIGGER_DEFINITIONS[triggerType],
    )
    .map((triggerType) => ({
      triggerType,
      ...SCAN_TRIGGER_DEFINITIONS[triggerType],
      ...SCAN_TRIGGER_DEFINITION_OVERRIDES[scanType]?.[triggerType],
    }));
};

export const getDefaultProfile = (scanType, profiles) =>
  profiles.find(({ name }) => name === DEFAULT_PROFILE_NAME_BY_SCAN_TYPE[scanType]) ??
  profiles.find(({ gitlabRecommended }) => gitlabRecommended) ??
  profiles[0];

export const managedByLabel = ({ gitlabRecommended }, rootGroupName) =>
  gitlabRecommended ? s__('ScanProfiles|GitLab') : rootGroupName || s__('ScanProfiles|Custom');

/**
 * Pick a name for a duplicated profile that no existing profile already claims.
 * The backend is the source of truth for uniqueness; this only saves a round trip.
 *
 * @param {string} name Name of the source profile.
 * @param {string[]} [existingNames] Names already in use in the namespace.
 * @returns {string} The first free name in the `(copy)`, `(copy 2)`, `(copy 3)` sequence.
 */
export const duplicateProfileName = (name, existingNames = []) => {
  const taken = new Set(existingNames.map((existingName) => existingName.toLowerCase()));
  let candidate = sprintf(s__('ScanProfiles|%{name} (copy)'), { name });

  for (let counter = 2; taken.has(candidate.toLowerCase()); counter += 1) {
    candidate = sprintf(s__('ScanProfiles|%{name} (copy %{counter})'), { name, counter });
  }

  return candidate;
};

const ANALYZER_CONFIGURATION_TYPES = [
  'SecretDetectionConfiguration',
  'SastConfiguration',
  'DependencyScanningConfiguration',
];
const UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: ['GIT_PUSH_EVENT'],
};
export const isTriggerConfigurable = (scanType, triggerType) =>
  !(UNCONFIGURABLE_TRIGGER_TYPES_BY_SCAN_TYPE[scanType] ?? []).includes(triggerType);

const configuredTriggerSettings = (triggerSettings = []) =>
  triggerSettings.filter((triggerSetting) => {
    const { __typename: typeName } = triggerSetting.configuration ?? {};
    return ANALYZER_CONFIGURATION_TYPES.includes(typeName);
  });

// Enum values come from a fixed set of options, and `''` can be one of them (e.g. imageSuffix's
// "Default"), so only `null`/`undefined` count as unset. Other types still treat an empty
// string/array as nothing configured.
export const isSetConfigurationValue = (value, valueType) => {
  if (Array.isArray(value)) return value.length > 0;
  if (valueType === VALUE_TYPE_ENUM) {
    return value !== null && value !== undefined;
  }
  return value !== null && value !== undefined && value !== '';
};

// A number input's min and max only steer its spinner, so a typed value can still be fractional
// or out of range. The GraphQL Int argument rejects either, so check them before saving.
export const isValidConfigurationValue = (definition = {}, value) => {
  if (definition.valueType !== VALUE_TYPE_NUMBER || !isSetConfigurationValue(value)) return true;
  const number = Number(value);
  return (
    isIntegerValue(value) &&
    (definition.min === undefined || number >= definition.min) &&
    (definition.max === undefined || number <= definition.max)
  );
};

export const numberInvalidFeedback = (variable, { min, max }) =>
  max === undefined
    ? sprintf(s__('ScanProfiles|%{variable} must be a whole number of %{min} or more.'), {
        variable,
        min,
      })
    : sprintf(s__('ScanProfiles|%{variable} must be a whole number from %{min} to %{max}.'), {
        variable,
        min,
        max,
      });

// Shared by classifyConfigurationVariables and buildEditableConfigurationRows: turns a
// `{ setting: [...] }` list plus a triggerType -> configuration map into one row per setting,
// collapsing to a single `value` when every enabled trigger agrees, or `varies: true` otherwise.
const buildProfileRows = ({
  settings,
  enabledTypes,
  configurationByTrigger,
  variableDefinitions,
}) =>
  settings
    .map((setting) => ({
      setting,
      triggerValues: enabledTypes
        .map((triggerType) => ({
          triggerType,
          value: configurationByTrigger.get(triggerType)?.[setting],
        }))
        .filter(({ value }) =>
          isSetConfigurationValue(value, variableDefinitions[setting]?.valueType),
        ),
    }))
    .filter(({ triggerValues }) => triggerValues.length > 0)
    .map((row) => {
      const sharesOneValue =
        row.triggerValues.length === enabledTypes.length &&
        row.triggerValues.every(({ value }) => isEqual(value, row.triggerValues[0].value));

      return sharesOneValue
        ? { ...row, value: row.triggerValues[0].value }
        : { ...row, varies: true };
    });

// Shared by classifyConfigurationVariables and buildEditableConfigurationRows: maps each enabled
// trigger type to its own `{ setting, value }` rows, every setting it sets rather than only the
// ones that differ across triggers.
const buildRowsByTrigger = ({
  settings,
  enabledTypes,
  configurationByTrigger,
  variableDefinitions,
}) =>
  new Map(
    enabledTypes.map((triggerType) => [
      triggerType,
      settings
        .map((setting) => ({
          setting,
          value: configurationByTrigger.get(triggerType)?.[setting],
        }))
        .filter(({ setting, value }) =>
          isSetConfigurationValue(value, variableDefinitions[setting]?.valueType),
        ),
    ]),
  );

/**
 * Classify a profile's per-trigger configuration into one row per setting.
 *
 * @param {string} scanType Scan type of the profile.
 * @param {string[]} [triggers] Enabled trigger types.
 * @param {Object[]} [triggerSettings] One `{ triggerType, configuration }` per trigger.
 * @returns {{profileRows: Object[], rowsByTrigger: Map, hasConfigurableTriggers: boolean}}
 *   `profileRows` holds one entry per set setting. Each carries `triggerValues`, one
 *   `{ triggerType, value }` per enabled trigger that sets it, and either the `value` every
 *   enabled configurable trigger shares or `varies: true` where they disagree. A trigger that
 *   leaves a setting unset is absent from `triggerValues` rather than present with no value.
 *   `rowsByTrigger` maps each enabled trigger type to its own `{ setting, value }` rows, every
 *   setting it sets rather than only the ones that differ.
 *   `hasConfigurableTriggers` is false when no enabled trigger accepts configuration.
 */
export const classifyConfigurationVariables = ({
  scanType,
  triggers = [],
  triggerSettings = [],
} = {}) => {
  const enabledTypes = triggers.filter((triggerType) =>
    isTriggerConfigurable(scanType, triggerType),
  );
  const configurationByTrigger = new Map(
    configuredTriggerSettings(translateTriggerSettingsFromGraphql(triggerSettings)).map(
      ({ triggerType, configuration }) => [triggerType, configuration],
    ),
  );
  const settings = [
    ...new Set(
      enabledTypes.flatMap((triggerType) =>
        Object.keys(configurationByTrigger.get(triggerType) ?? {}).filter(
          (key) => key !== '__typename',
        ),
      ),
    ),
  ];
  const variableDefinitions = variableDefinitionsFor(scanType);

  const profileRows = buildProfileRows({
    settings,
    enabledTypes,
    configurationByTrigger,
    variableDefinitions,
  });

  const rowsByTrigger = buildRowsByTrigger({
    settings,
    enabledTypes,
    configurationByTrigger,
    variableDefinitions,
  });

  return { profileRows, rowsByTrigger, hasConfigurableTriggers: enabledTypes.length > 0 };
};

/**
 * Same row shape as classifyConfigurationVariables, but sourced from the edit form's live
 * `triggerConfigurations` draft (`{ [triggerType]: { [setting]: value } }`) rather than the
 * raw GraphQL `triggerSettings` the profile was fetched with.
 *
 * @param {string} scanType Scan type of the profile.
 * @param {string[]} [enabledTriggers] Currently enabled trigger types.
 * @param {Object} [triggerConfigurations] Values keyed by trigger type, then by setting.
 * @returns {{rows: Object[], rowsByTrigger: Map, configurableTriggers: string[],
 *   hasConfigurableTriggers: boolean, hasEnabledTriggers: boolean}} `hasEnabledTriggers` is true
 *   whenever any trigger is enabled, even if none of them support configuration;
 *   `hasConfigurableTriggers` is only true when at least one enabled trigger does.
 */
export const buildEditableConfigurationRows = ({
  scanType,
  enabledTriggers = [],
  triggerConfigurations = {},
} = {}) => {
  const configurableTriggers = enabledTriggers.filter((triggerType) =>
    isTriggerConfigurable(scanType, triggerType),
  );
  const configurationByTrigger = new Map(
    configurableTriggers.map((triggerType) => [
      triggerType,
      triggerConfigurations[triggerType] ?? {},
    ]),
  );
  const variableDefinitions = variableDefinitionsFor(scanType);
  const catalogOrder = Object.keys(variableDefinitions);
  const position = (setting) => {
    const index = catalogOrder.indexOf(setting);
    return index === -1 ? catalogOrder.length : index;
  };
  const settings = [
    ...new Set(
      configurableTriggers.flatMap((triggerType) =>
        Object.keys(triggerConfigurations[triggerType] ?? {}),
      ),
    ),
  ].sort((a, b) => position(a) - position(b));

  const rows = buildProfileRows({
    settings,
    enabledTypes: configurableTriggers,
    configurationByTrigger,
    variableDefinitions,
  }).map((row) => ({
    ...row,
    // Once at least one trigger has this setting, pad in the rest of the configurable triggers
    // too, even ones that don't have a value yet. Otherwise, removing a trigger's value drops it
    // from the row entirely, with no way to give it a value again short of the setting being
    // fully unset and re-added through the Add-variable flow.
    triggerValues: configurableTriggers.map(
      (triggerType) =>
        row.triggerValues.find((triggerValue) => triggerValue.triggerType === triggerType) ?? {
          triggerType,
          value: null,
        },
    ),
  }));

  const rowsByTrigger = buildRowsByTrigger({
    settings,
    enabledTypes: configurableTriggers,
    configurationByTrigger,
    variableDefinitions,
  });

  return {
    rows,
    rowsByTrigger,
    configurableTriggers,
    hasConfigurableTriggers: configurableTriggers.length > 0,
    hasEnabledTriggers: enabledTriggers.length > 0,
  };
};

// A boolean's raw `true`/`false`, or an enum's raw option value (e.g. imageSuffix's "Default" is
// `''`), isn't user-facing copy. Maps it to the same label the editable radio group / dropdown
// uses for it, falling back to the raw value for settings with no catalog of display labels.
export const displayConfigurationValue = (definition, value) => {
  if (definition.valueType === VALUE_TYPE_BOOLEAN) {
    return BOOLEAN_OPTIONS.find((option) => option.value === value)?.text ?? value;
  }
  if (definition.valueType === VALUE_TYPE_ENUM) {
    return (definition.options ?? []).find((option) => option.value === value)?.text ?? value;
  }
  if (definition.valueType === VALUE_TYPE_MULTI_SELECT && Array.isArray(value)) {
    const options = definition.options ?? [];
    const optionValues = options.map((option) => option.value);
    return [
      ...options.filter((option) => value.includes(option.value)).map((option) => option.text),
      ...value.filter((item) => !optionValues.includes(item)),
    ].join(', ');
  }
  if (Array.isArray(value)) {
    return value.join(', ');
  }
  return value;
};

export const multiSelectToggleText = (definition, value) => {
  const labels = (definition.options ?? [])
    .filter((option) => (value ?? []).includes(option.value))
    .map((option) => option.text);
  return labels.length ? labels.join(', ') : definition.placeholder;
};

export const textToStringList = (text) =>
  text
    .split(/[\n,]/)
    .map((line) => line.trim())
    .filter(Boolean);
