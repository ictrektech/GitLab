import {
  scanTypeName,
  scanTypeSentenceCase,
  scanTypeHelpLink,
  isScanProfileTypeVisible,
  resolveTriggers,
  allowedTriggersFor,
  getDefaultProfile,
  classifyConfigurationVariables,
  buildEditableConfigurationRows,
  isTriggerConfigurable,
  managedByLabel,
  duplicateProfileName,
  textToStringList,
  displayConfigurationValue,
  isValidConfigurationValue,
  multiSelectToggleText,
  numberInvalidFeedback,
} from 'ee/security_configuration/components/scan_profiles/utils';
import {
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING,
  VALUE_TYPE_STRING_LIST,
} from 'ee/security_configuration/components/scan_profiles/variable_definitions';
import {
  SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
} from '~/security_configuration/constants';

const MERGE_REQUEST = 'MERGE_REQUEST_PIPELINE';
const DEFAULT_BRANCH = 'DEFAULT_BRANCH_PIPELINE';
const GIT_PUSH = 'GIT_PUSH_EVENT';

const HISTORIC_SCAN = 'historicScan';
const EXCLUDED_PATHS = 'excludedPaths';

const buildConfiguration = (values) => ({
  __typename: 'SecretDetectionConfiguration',
  secureAnalyzersPrefix: null,
  imageSuffix: null,
  historicScan: null,
  logOptions: null,
  excludedPaths: null,
  rulesetGitReference: null,
  ...values,
});

const buildSetting = (triggerType, values) => ({
  triggerType,
  configuration: values ? buildConfiguration(values) : null,
});

const classify = ({ triggers, triggerSettings, scanType = SCAN_PROFILE_TYPE_SECRET_DETECTION }) =>
  classifyConfigurationVariables({ scanType, triggers, triggerSettings });

describe('scan profile utils', () => {
  describe('scanTypeName', () => {
    it('names a known scan type', () => {
      expect(scanTypeName(SCAN_PROFILE_TYPE_SECRET_DETECTION)).toBe('Secret detection');
    });

    it('names the business logic scan type', () => {
      expect(scanTypeName(SCAN_PROFILE_TYPE_BUSINESS_LOGIC)).toBe('Business logic');
    });

    it('falls back to the raw value for an unknown scan type', () => {
      expect(scanTypeName('NOT_A_SCANNER')).toBe('NOT_A_SCANNER');
    });
  });

  describe('scanTypeSentenceCase', () => {
    it('lowercases the leading letter of a Title Case name', () => {
      expect(scanTypeSentenceCase(SCAN_PROFILE_TYPE_SECRET_DETECTION)).toBe('secret detection');
    });

    it('keeps an all-caps acronym as-is', () => {
      expect(scanTypeSentenceCase(SCAN_PROFILE_TYPE_SAST)).toBe('SAST');
    });
  });

  describe('scanTypeHelpLink', () => {
    it('links to the help page for a known scan type', () => {
      expect(scanTypeHelpLink(SCAN_PROFILE_TYPE_SAST)).toBe(
        '/help/user/application_security/sast/_index',
      );
    });

    it('links business logic to its docs page', () => {
      expect(scanTypeHelpLink(SCAN_PROFILE_TYPE_BUSINESS_LOGIC)).toBe(
        '/help/user/application_security/business_logic_scanning/_index',
      );
    });

    it('has no link for an unknown scan type', () => {
      expect(scanTypeHelpLink('NOT_A_SCANNER')).toBeUndefined();
    });
  });

  describe('isScanProfileTypeVisible', () => {
    it('shows a scan type with a category', () => {
      expect(isScanProfileTypeVisible('SAST')).toBe(true);
    });

    it('hides a scan type without a category', () => {
      expect(isScanProfileTypeVisible('NOT_A_SCANNER')).toBe(false);
    });

    it('shows triage with the feature flag enabled', () => {
      window.gon.features = { triageAndRemediationProfilesUi: true };

      expect(isScanProfileTypeVisible('TRIAGE_AND_REMEDIATION')).toBe(true);
    });

    it('hides triage with the feature flag disabled', () => {
      window.gon.features = { triageAndRemediationProfilesUi: false };

      expect(isScanProfileTypeVisible('TRIAGE_AND_REMEDIATION')).toBe(false);
    });
  });

  describe('managedByLabel', () => {
    it('returns GitLab for a recommended profile', () => {
      expect(managedByLabel({ gitlabRecommended: true }, 'Acme Corp')).toBe('GitLab');
    });

    it('returns the owning group name', () => {
      expect(managedByLabel({ gitlabRecommended: false }, 'Acme Corp')).toBe('Acme Corp');
    });

    it('returns Custom without a group name', () => {
      expect(managedByLabel({ gitlabRecommended: false }, '')).toBe('Custom');
    });
  });

  describe('duplicateProfileName', () => {
    it('suffixes the source name with (copy)', () => {
      expect(duplicateProfileName('My profile')).toBe('My profile (copy)');
    });

    it('ignores names already in use by other profiles', () => {
      expect(duplicateProfileName('My profile', ['Another profile'])).toBe('My profile (copy)');
    });

    it('numbers the copy when (copy) is taken', () => {
      expect(duplicateProfileName('My profile', ['My profile', 'My profile (copy)'])).toBe(
        'My profile (copy 2)',
      );
    });

    it('keeps counting until it finds a free name', () => {
      const taken = ['My profile (copy)', 'My profile (copy 2)', 'My profile (copy 3)'];

      expect(duplicateProfileName('My profile', taken)).toBe('My profile (copy 4)');
    });

    it('treats existing names as taken regardless of case', () => {
      expect(duplicateProfileName('My profile', ['MY PROFILE (COPY)'])).toBe('My profile (copy 2)');
    });
  });

  describe('resolveTriggers', () => {
    it('resolves each trigger type to its definition', () => {
      const triggers = resolveTriggers(
        [MERGE_REQUEST, GIT_PUSH],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );

      expect(triggers.map(({ anchor }) => anchor)).toEqual([
        'merge-request-pipeline',
        'secret-push-protection',
      ]);
    });

    it('includes the triggerType on each resolved definition', () => {
      const triggers = resolveTriggers(
        [MERGE_REQUEST, GIT_PUSH],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );

      expect(triggers.map(({ triggerType }) => triggerType)).toEqual([MERGE_REQUEST, GIT_PUSH]);
    });

    it('drops a trigger type the scan type does not allow', () => {
      const triggers = resolveTriggers(
        [MERGE_REQUEST, 'NOT_A_TRIGGER'],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );

      expect(triggers.map(({ anchor }) => anchor)).toEqual(['merge-request-pipeline']);
    });

    it.each([null, undefined, []])('returns an empty list for %p', (triggers) => {
      expect(resolveTriggers(triggers)).toEqual([]);
    });

    it('uses the scan type override for business logic merge request pipelines', () => {
      const [trigger] = resolveTriggers([MERGE_REQUEST], SCAN_PROFILE_TYPE_BUSINESS_LOGIC);

      expect(trigger.anchor).toBe('merge-request-pipeline');
      expect(trigger.infoDescription).toContain('files a merge request changes');
    });

    it('keeps the generic text for other scan types', () => {
      const [trigger] = resolveTriggers([MERGE_REQUEST], SCAN_PROFILE_TYPE_SAST);

      expect(trigger.infoDescription).not.toContain('files a merge request changes');
    });

    it('orders triggers by the canonical order for the scan type, regardless of input order', () => {
      const triggers = resolveTriggers(
        [GIT_PUSH, DEFAULT_BRANCH, MERGE_REQUEST],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );

      expect(triggers.map(({ anchor }) => anchor)).toEqual([
        'merge-request-pipeline',
        'default-branch-pipeline',
        'secret-push-protection',
      ]);
    });

    it('keeps the same order after a trigger is disabled and re-enabled', () => {
      const reordered = resolveTriggers(
        [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );
      const original = resolveTriggers(
        [GIT_PUSH, MERGE_REQUEST, DEFAULT_BRANCH],
        SCAN_PROFILE_TYPE_SECRET_DETECTION,
      );

      expect(reordered.map(({ anchor }) => anchor)).toEqual(original.map(({ anchor }) => anchor));
    });
  });

  describe('allowedTriggersFor', () => {
    it('lists all three secret detection triggers', () => {
      expect(allowedTriggersFor(SCAN_PROFILE_TYPE_SECRET_DETECTION)).toEqual([
        'MERGE_REQUEST_PIPELINE',
        'DEFAULT_BRANCH_PIPELINE',
        'GIT_PUSH_EVENT',
      ]);
    });

    it('lists only pipeline triggers for SAST (no push-time trigger)', () => {
      expect(allowedTriggersFor(SCAN_PROFILE_TYPE_SAST)).toEqual([
        'MERGE_REQUEST_PIPELINE',
        'DEFAULT_BRANCH_PIPELINE',
      ]);
    });

    it('returns pipeline triggers for dependency scanning', () => {
      expect(allowedTriggersFor('DEPENDENCY_SCANNING')).toEqual([
        'MERGE_REQUEST_PIPELINE',
        'DEFAULT_BRANCH_PIPELINE',
      ]);
    });

    it('lists only the merge request pipeline trigger for business logic', () => {
      expect(allowedTriggersFor(SCAN_PROFILE_TYPE_BUSINESS_LOGIC)).toEqual([
        'MERGE_REQUEST_PIPELINE',
      ]);
    });

    it('returns an empty list for an unknown scan type', () => {
      expect(allowedTriggersFor('NOT_A_SCANNER')).toEqual([]);
    });
  });

  describe('getDefaultProfile', () => {
    const custom = { id: 'custom', name: 'Custom', gitlabRecommended: false };
    const recommended = { id: 'recommended', name: 'SAST (default)', gitlabRecommended: true };
    const conservative = {
      id: 'conservative',
      name: 'Triage and Remediation (Conservative)',
      gitlabRecommended: true,
    };
    const standard = {
      id: 'standard',
      name: 'Triage and Remediation (Standard)',
      gitlabRecommended: true,
    };

    it('returns the standard preset for triage', () => {
      expect(
        getDefaultProfile(SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION, [
          custom,
          conservative,
          standard,
        ]),
      ).toBe(standard);
    });

    it('returns a recommended triage preset as fallback', () => {
      expect(
        getDefaultProfile(SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION, [custom, conservative]),
      ).toBe(conservative);
    });

    it('returns the recommended profile for other types', () => {
      expect(getDefaultProfile(SCAN_PROFILE_TYPE_SAST, [custom, recommended])).toBe(recommended);
    });

    it('returns the first profile if none is recommended', () => {
      expect(getDefaultProfile(SCAN_PROFILE_TYPE_SAST, [custom])).toBe(custom);
    });
  });

  describe('isTriggerConfigurable', () => {
    it.each`
      scanType                              | triggerType      | expected
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${MERGE_REQUEST} | ${true}
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${GIT_PUSH}      | ${false}
      ${SCAN_PROFILE_TYPE_SECRET_DETECTION} | ${'FUTURE_TYPE'} | ${true}
      ${'SAST'}                             | ${GIT_PUSH}      | ${true}
    `('is $expected for $scanType and $triggerType', ({ scanType, triggerType, expected }) => {
      expect(isTriggerConfigurable(scanType, triggerType)).toBe(expected);
    });
  });

  describe('classifyConfigurationVariables', () => {
    describe('hasConfigurableTriggers', () => {
      it.each`
        description                            | triggers                     | expected
        ${'a configurable trigger is enabled'} | ${[MERGE_REQUEST, GIT_PUSH]} | ${true}
        ${'only the unconfigurable one is'}    | ${[GIT_PUSH]}                | ${false}
        ${'no trigger is enabled'}             | ${[]}                        | ${false}
      `('is $expected when $description', ({ triggers, expected }) => {
        expect(classify({ triggers, triggerSettings: [] }).hasConfigurableTriggers).toBe(expected);
      });
    });

    describe('when every configurable trigger is enabled', () => {
      const triggers = [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH];

      it('returns a shared value with a row per trigger', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
            buildSetting(GIT_PUSH, null),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            value: true,
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: true },
              { triggerType: DEFAULT_BRANCH, value: true },
            ],
          },
        ]);
      });

      it('returns varies and a row per disagreeing trigger', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: false }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: false },
              { triggerType: DEFAULT_BRANCH, value: true },
            ],
          },
        ]);
      });

      it('treats set on one and unset on the other as varying', () => {
        const { profileRows } = classify({
          triggers,
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(DEFAULT_BRANCH, {}),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [{ triggerType: MERGE_REQUEST, value: true }],
          },
        ]);
      });
    });

    describe('when a configurable trigger is disabled', () => {
      it('ignores it and reports the enabled trigger value as the profile value', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, GIT_PUSH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true }),
            buildSetting(GIT_PUSH, null),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            value: true,
            triggerValues: [{ triggerType: MERGE_REQUEST, value: true }],
          },
        ]);
      });

      it('returns trigger values for the enabled triggers', () => {
        const { profileRows } = classify({
          triggers: [DEFAULT_BRANCH, GIT_PUSH],
          triggerSettings: [
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
            buildSetting(GIT_PUSH, { historicScan: false }),
          ],
        });

        expect(profileRows[0].triggerValues).toEqual([
          { triggerType: DEFAULT_BRANCH, value: true },
        ]);
      });
    });

    describe('values it should leave out', () => {
      it('returns nothing when no field is set', () => {
        const { profileRows, hasConfigurableTriggers } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [buildSetting(MERGE_REQUEST, {}), buildSetting(DEFAULT_BRANCH, {})],
        });

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(true);
      });

      it('ignores configuration on a trigger that cannot be configured', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH],
          triggerSettings: [buildSetting(GIT_PUSH, { historicScan: true })],
        });

        expect(profileRows).toEqual([]);
      });

      it('returns nothing when the only enabled trigger cannot be configured', () => {
        const { profileRows, hasConfigurableTriggers } = classify({
          triggers: [GIT_PUSH],
          triggerSettings: [buildSetting(GIT_PUSH, null)],
        });

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(false);
      });

      it('returns nothing when called with no arguments', () => {
        const { profileRows, hasConfigurableTriggers } = classifyConfigurationVariables();

        expect(profileRows).toEqual([]);
        expect(hasConfigurableTriggers).toBe(false);
      });
    });

    describe('what counts as unset', () => {
      it.each`
        description       | value
        ${'empty list'}   | ${[]}
        ${'empty string'} | ${''}
        ${'null'}         | ${null}
      `('ignores a field set to an $description', ({ value }) => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { logOptions: value }),
            buildSetting(DEFAULT_BRANCH, { logOptions: value }),
          ],
        });

        expect(profileRows).toEqual([]);
      });

      it('keeps a field set to false', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: false }),
            buildSetting(DEFAULT_BRANCH, { historicScan: false }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].setting).toBe(HISTORIC_SCAN);
        expect(profileRows[0].value).toBe(false);
      });

      it('keeps an enum field explicitly set to the empty-string Default option', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { imageSuffix: '' }),
            buildSetting(DEFAULT_BRANCH, { imageSuffix: '' }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].setting).toBe('imageSuffix');
        expect(profileRows[0].value).toBe('');
      });
    });

    describe('SAST configuration', () => {
      it('returns the settings a SAST profile shares across its triggers', () => {
        const sastSetting = (triggerType) => ({
          triggerType,
          configuration: {
            __typename: 'SastConfiguration',
            secureAnalyzersPrefix: null,
            imageSuffix: null,
            analyzerImageTag: null,
            excludedAnalyzers: ['bandit'],
            excludedPaths: null,
            advancedSastPartialScan: null,
            gitlabAdvSastIncrScan: null,
          },
        });

        const { profileRows } = classify({
          scanType: SCAN_PROFILE_TYPE_SAST,
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [sastSetting(MERGE_REQUEST), sastSetting(DEFAULT_BRANCH)],
        });

        expect(profileRows).toEqual([
          {
            setting: 'excludedAnalyzers',
            value: ['bandit'],
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: ['bandit'] },
              { triggerType: DEFAULT_BRANCH, value: ['bandit'] },
            ],
          },
        ]);
      });
    });

    describe('dependency scanning configuration', () => {
      it('returns the settings shared across triggers', () => {
        const dependencyScanningSetting = (triggerType) => ({
          triggerType,
          configuration: {
            __typename: 'DependencyScanningConfiguration',
            secureAnalyzersPrefix: null,
            maxDepth: 3,
            excludedPaths: null,
          },
        });

        const { profileRows } = classify({
          scanType: 'DEPENDENCY_SCANNING',
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            dependencyScanningSetting(MERGE_REQUEST),
            dependencyScanningSetting(DEFAULT_BRANCH),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: 'maxDepth',
            value: 3,
            triggerValues: [
              { triggerType: MERGE_REQUEST, value: 3 },
              { triggerType: DEFAULT_BRANCH, value: 3 },
            ],
          },
        ]);
      });
    });

    describe('configuration of another type', () => {
      it('ignores a configuration that is not an analyzer configuration', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            {
              triggerType: MERGE_REQUEST,
              configuration: {
                __typename: 'AutoRemediationConfiguration',
                historicScan: true,
                excludedPaths: ['spec/'],
              },
            },
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(profileRows).toEqual([
          {
            setting: HISTORIC_SCAN,
            varies: true,
            triggerValues: [{ triggerType: DEFAULT_BRANCH, value: true }],
          },
        ]);
      });
    });

    describe('rowsByTrigger', () => {
      it('returns every setting a trigger sets', () => {
        const { rowsByTrigger } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { historicScan: true, excludedPaths: ['spec/'] }),
            buildSetting(DEFAULT_BRANCH, { historicScan: true }),
          ],
        });

        expect(rowsByTrigger.get(MERGE_REQUEST)).toEqual([
          { setting: 'historicScan', value: true },
          { setting: 'excludedPaths', value: ['spec/'] },
        ]);
        expect(rowsByTrigger.get(DEFAULT_BRANCH)).toEqual([
          { setting: 'historicScan', value: true },
        ]);
      });
    });

    describe('comparing values', () => {
      it.each`
        first         | second
        ${['a, b']}   | ${['a', 'b']}
        ${['b', 'a']} | ${['a', 'b']}
        ${['a', 'b']} | ${['a', 'c']}
      `('treats $first and $second as varying', ({ first, second }) => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { excludedPaths: first }),
            buildSetting(DEFAULT_BRANCH, { excludedPaths: second }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].varies).toBe(true);
      });

      it('promotes an identical list to the profile value', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { excludedPaths: ['a', 'b'] }),
            buildSetting(DEFAULT_BRANCH, { excludedPaths: ['a', 'b'] }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].setting).toBe(EXCLUDED_PATHS);
        expect(profileRows[0].value).toEqual(['a', 'b']);
      });
    });

    describe('values', () => {
      it('passes secureAnalyzersPrefix through as stored', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { secureAnalyzersPrefix: 'my-registry' }),
            buildSetting(DEFAULT_BRANCH, { secureAnalyzersPrefix: 'my-registry' }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].value).toEqual('my-registry');
      });

      it('translates a GraphQL enum name (e.g. imageSuffix FIPS) to the backend value', () => {
        const { profileRows } = classify({
          triggers: [MERGE_REQUEST, DEFAULT_BRANCH],
          triggerSettings: [
            buildSetting(MERGE_REQUEST, { imageSuffix: 'FIPS' }),
            buildSetting(DEFAULT_BRANCH, { imageSuffix: 'FIPS' }),
          ],
        });

        expect(profileRows).toHaveLength(1);
        expect(profileRows[0].value).toEqual('-fips');
      });
    });
  });

  describe('buildEditableConfigurationRows', () => {
    const buildRows = ({ enabledTriggers, triggerConfigurations }) =>
      buildEditableConfigurationRows({
        scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
        enabledTriggers,
        triggerConfigurations,
      });

    it('reports no configurable triggers when only the unconfigurable one is enabled', () => {
      const { configurableTriggers, rows } = buildRows({
        enabledTriggers: [GIT_PUSH],
        triggerConfigurations: {},
      });

      expect(configurableTriggers).toEqual([]);
      expect(rows).toEqual([]);
    });

    it('reports no configurable triggers when none are enabled', () => {
      const { configurableTriggers, rows } = buildRows({
        enabledTriggers: [],
        triggerConfigurations: {},
      });

      expect(configurableTriggers).toEqual([]);
      expect(rows).toEqual([]);
    });

    it('lists the configurable triggers, excluding the unconfigurable one', () => {
      const { configurableTriggers } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH, GIT_PUSH],
        triggerConfigurations: {},
      });

      expect(configurableTriggers).toEqual([MERGE_REQUEST, DEFAULT_BRANCH]);
    });

    it('returns no rows when nothing is configured yet', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {},
      });

      expect(rows).toEqual([]);
    });

    it('collapses a shared value across every enabled configurable trigger', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {
          [MERGE_REQUEST]: { [HISTORIC_SCAN]: true },
          [DEFAULT_BRANCH]: { [HISTORIC_SCAN]: true },
        },
      });

      expect(rows).toEqual([
        { setting: HISTORIC_SCAN, value: true, triggerValues: expect.any(Array) },
      ]);
    });

    it('marks a row as varying when triggers disagree', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {
          [MERGE_REQUEST]: { [HISTORIC_SCAN]: true },
          [DEFAULT_BRANCH]: { [HISTORIC_SCAN]: false },
        },
      });

      expect(rows[0].varies).toBe(true);
      expect(rows[0].triggerValues).toEqual([
        { triggerType: MERGE_REQUEST, value: true },
        { triggerType: DEFAULT_BRANCH, value: false },
      ]);
    });

    it('keeps an enum setting explicitly set to the empty-string Default option', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {
          [MERGE_REQUEST]: { imageSuffix: '' },
          [DEFAULT_BRANCH]: { imageSuffix: '' },
        },
      });

      expect(rows).toEqual([
        { setting: 'imageSuffix', value: '', triggerValues: expect.any(Array) },
      ]);
    });

    it('leaves out a setting once removed from every trigger', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {
          [MERGE_REQUEST]: {},
          [DEFAULT_BRANCH]: {},
        },
      });

      expect(rows).toEqual([]);
    });

    it('ignores configuration left on a trigger the user has since disabled', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST],
        triggerConfigurations: {
          [MERGE_REQUEST]: { [HISTORIC_SCAN]: true },
          [DEFAULT_BRANCH]: { [HISTORIC_SCAN]: true },
        },
      });

      expect(rows).toEqual([
        { setting: HISTORIC_SCAN, value: true, triggerValues: expect.any(Array) },
      ]);
      expect(rows[0].triggerValues).toEqual([{ triggerType: MERGE_REQUEST, value: true }]);
    });

    it('keeps a placeholder for a trigger whose value was removed, instead of dropping it from the row', () => {
      const { rows } = buildRows({
        enabledTriggers: [MERGE_REQUEST, DEFAULT_BRANCH],
        triggerConfigurations: {
          [MERGE_REQUEST]: { [HISTORIC_SCAN]: true },
          [DEFAULT_BRANCH]: {},
        },
      });

      expect(rows).toHaveLength(1);
      expect(rows[0].setting).toBe(HISTORIC_SCAN);
      expect(rows[0].varies).toBe(true);
      expect(rows[0].triggerValues).toEqual([
        { triggerType: MERGE_REQUEST, value: true },
        { triggerType: DEFAULT_BRANCH, value: null },
      ]);
    });
  });

  describe('textToStringList', () => {
    it('return each comma-separated item on one line', () => {
      expect(textToStringList('semgrep, test, this_is_broken!!')).toEqual([
        'semgrep',
        'test',
        'this_is_broken!!',
      ]);
    });

    it('return items separated by commas and newlines', () => {
      expect(textToStringList('semgrep, test\nspotbugs')).toEqual(['semgrep', 'test', 'spotbugs']);
    });

    it('remove stray spaces and empty items', () => {
      expect(textToStringList('  semgrep ,, \n\n test ,')).toEqual(['semgrep', 'test']);
    });
  });

  describe('displayConfigurationValue', () => {
    it('maps a boolean value to its Enabled/Disabled label', () => {
      const definition = { valueType: VALUE_TYPE_BOOLEAN };

      expect(displayConfigurationValue(definition, true)).toBe('Enabled');
      expect(displayConfigurationValue(definition, false)).toBe('Disabled');
    });

    it('maps an enum value to its option label, including the empty-string option', () => {
      const definition = {
        valueType: VALUE_TYPE_ENUM,
        options: [
          { value: '', text: 'Default' },
          { value: '-fips', text: 'FIPS' },
        ],
      };

      expect(displayConfigurationValue(definition, '')).toBe('Default');
      expect(displayConfigurationValue(definition, '-fips')).toBe('FIPS');
    });

    it('returns multi-select labels in option order', () => {
      const definition = {
        valueType: VALUE_TYPE_MULTI_SELECT,
        options: [
          { value: 'maven', text: 'Maven' },
          { value: 'python', text: 'Python' },
        ],
      };

      expect(displayConfigurationValue(definition, ['python', 'maven'])).toBe('Maven, Python');
    });

    it('returns unmatched multi-select values last', () => {
      const definition = {
        valueType: VALUE_TYPE_MULTI_SELECT,
        options: [{ value: 'maven', text: 'Maven' }],
      };

      expect(displayConfigurationValue(definition, ['sbt', 'maven'])).toBe('Maven, sbt');
    });

    it('returns a string list joined by commas', () => {
      const definition = { valueType: VALUE_TYPE_STRING_LIST };

      expect(displayConfigurationValue(definition, ['spec/', 'tmp/'])).toBe('spec/, tmp/');
    });

    it('falls back to the raw value for a value type with no label catalog', () => {
      const definition = { valueType: VALUE_TYPE_STRING };

      expect(displayConfigurationValue(definition, 'registry.example.com')).toBe(
        'registry.example.com',
      );
    });

    it('falls back to the raw value when no definition is found for the setting', () => {
      expect(displayConfigurationValue({}, 'spec/**')).toBe('spec/**');
    });
  });

  describe('isValidConfigurationValue', () => {
    const definition = { valueType: VALUE_TYPE_NUMBER, min: 5, max: 300 };

    it.each([
      ['30', true],
      [30, true],
      ['', true],
      [null, true],
      ['500', false],
      ['1.5', false],
      ['30.0', false],
      ['1e2', false],
      ['4', false],
    ])('returns whether %p is a valid apiTimeout', (value, expected) => {
      expect(isValidConfigurationValue(definition, value)).toBe(expected);
    });

    it('returns true for a value type other than number', () => {
      expect(isValidConfigurationValue({ valueType: VALUE_TYPE_STRING }, '1.5')).toBe(true);
    });
  });

  describe('numberInvalidFeedback', () => {
    it('returns the range given a max', () => {
      expect(numberInvalidFeedback('apiTimeout', { min: 5, max: 300 })).toBe(
        'apiTimeout must be a whole number from 5 to 300.',
      );
    });

    it('returns the lower bound given no max', () => {
      expect(numberInvalidFeedback('maxDepth', { min: -1 })).toBe(
        'maxDepth must be a whole number of -1 or more.',
      );
    });
  });

  describe('multiSelectToggleText', () => {
    const definition = {
      options: [
        { value: 'maven', text: 'Maven' },
        { value: 'gradle', text: 'Gradle' },
        { value: 'python', text: 'Python' },
      ],
      placeholder: 'Select jobs to skip',
    };

    it('returns the selected labels in option order', () => {
      expect(multiSelectToggleText(definition, ['python', 'maven'])).toBe('Maven, Python');
    });

    it.each([[[]], [null]])('returns the placeholder for a %p selection', (value) => {
      expect(multiSelectToggleText(definition, value)).toBe('Select jobs to skip');
    });
  });
});
