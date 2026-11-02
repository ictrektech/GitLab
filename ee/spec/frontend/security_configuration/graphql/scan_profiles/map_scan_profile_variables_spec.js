import dependencyScanningCreateResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql.dependency_scanning.json';
import sastCreateResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql.sast.json';
import createResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql.json';
import fanOutResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.json';
import mergedResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.merged.json';
import perTriggerResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.per_trigger.json';
import toggledOffResponse from 'test_fixtures/graphql/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql.toggled_off.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import securityScanProfileCreateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_create.mutation.graphql';
import securityScanProfileUpdateMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_update.mutation.graphql';
import {
  isTriggerConfigurable,
  mapScanProfileVariables,
  buildScanProfileUpdateInput,
  buildScanProfileCreateInput,
  readScanProfileTriggers,
  translateTriggerSettingsFromGraphql,
} from 'ee/security_configuration/graphql/scan_profiles/map_scan_profile_variables';

const SCAN_TYPE = 'SECRET_DETECTION';
const PROFILE_ID = 'gid://gitlab/Security::ScanProfile/10';
const NAMESPACE_ID = 'gid://gitlab/Group/7';
const PREFIX = 'registry.gitlab.com/security-products';
const ALL_TRIGGERS = ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE', 'GIT_PUSH_EVENT'];
const PROFILE_CONFIGURATION = { secureAnalyzersPrefix: PREFIX, historicScan: true };

const mutate = async ({ mutation, response, input }) => {
  const handler = jest.fn().mockResolvedValue(response);
  const { defaultClient } = createMockApollo([[mutation, handler]]);
  const { data } = await defaultClient.mutate({ mutation, variables: { input } });

  return { data, handler };
};

const update = async ({ response, input }) => {
  const { data, handler } = await mutate({
    mutation: securityScanProfileUpdateMutation,
    response,
    input,
  });

  return { handler, scanProfile: data.securityScanProfileUpdate.scanProfile };
};

const updateInput = (overrides = {}) =>
  buildScanProfileUpdateInput({
    profileId: PROFILE_ID,
    scanType: SCAN_TYPE,
    enabledTriggers: ALL_TRIGGERS,
    profileConfiguration: PROFILE_CONFIGURATION,
    ...overrides,
  });

it('treats every secret detection trigger except GIT_PUSH_EVENT as configurable', () => {
  expect(isTriggerConfigurable(SCAN_TYPE, 'MERGE_REQUEST_PIPELINE')).toBe(true);
  expect(isTriggerConfigurable(SCAN_TYPE, 'DEFAULT_BRANCH_PIPELINE')).toBe(true);
  expect(isTriggerConfigurable(SCAN_TYPE, 'GIT_PUSH_EVENT')).toBe(false);
});

it('treats every SAST trigger as configurable', () => {
  expect(isTriggerConfigurable('SAST', 'MERGE_REQUEST_PIPELINE')).toBe(true);
  expect(isTriggerConfigurable('SAST', 'DEFAULT_BRANCH_PIPELINE')).toBe(true);
});

it('nests SAST profile-level variables under the sast configuration key', () => {
  const sastConfiguration = {
    secureAnalyzersPrefix: 'registry.example.com/security-products',
    excludedAnalyzers: ['pmd-apex'],
  };

  const triggers = mapScanProfileVariables({
    scanType: 'SAST',
    enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
    profileConfiguration: sastConfiguration,
  });

  expect(triggers).toEqual([
    { triggerType: 'MERGE_REQUEST_PIPELINE', configuration: { sast: sastConfiguration } },
    { triggerType: 'DEFAULT_BRANCH_PIPELINE', configuration: { sast: sastConfiguration } },
  ]);
});

it('sends every enabled trigger bare when no variables are set', () => {
  const triggers = mapScanProfileVariables({ scanType: SCAN_TYPE, enabledTriggers: ALL_TRIGGERS });

  expect(triggers).toEqual([
    { triggerType: 'MERGE_REQUEST_PIPELINE' },
    { triggerType: 'DEFAULT_BRANCH_PIPELINE' },
    { triggerType: 'GIT_PUSH_EVENT' },
  ]);
});

it('fans profile-level variables out to each configurable trigger', async () => {
  const input = updateInput();

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: fanOutResponse, input });
  const { enabledTriggers, triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(enabledTriggers).toHaveLength(3);
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION,
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});

it('keeps trigger-level variables with their own trigger', async () => {
  const triggerConfigurations = {
    MERGE_REQUEST_PIPELINE: { historicScan: false, excludedPaths: ['spec/fixtures/**'] },
    DEFAULT_BRANCH_PIPELINE: { historicScan: true },
  };
  const input = updateInput({ profileConfiguration: undefined, triggerConfigurations });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: perTriggerResponse, input });
  const { triggerConfigurations: storedConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            secretDetection: { historicScan: false, excludedPaths: ['spec/fixtures/**'] },
          },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: { historicScan: true } },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(storedConfigurations).toEqual(triggerConfigurations);
});

it('lets a trigger-level value override the profile-level one key by key', async () => {
  const input = updateInput({
    triggerConfigurations: {
      MERGE_REQUEST_PIPELINE: { historicScan: false },
      GIT_PUSH_EVENT: { historicScan: true },
    },
  });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: mergedResponse, input });
  const { triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            secretDetection: { secureAnalyzersPrefix: PREFIX, historicScan: false },
          },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: { secureAnalyzersPrefix: PREFIX, historicScan: false },
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});

it('drops a toggled-off trigger from the payload and sees it destroyed in the response', async () => {
  const input = updateInput({ enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'GIT_PUSH_EVENT'] });

  const {
    handler,
    scanProfile: { triggerSettings },
  } = await update({ response: toggledOffResponse, input });
  const { enabledTriggers, triggerConfigurations } = readScanProfileTriggers(triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      id: PROFILE_ID,
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });

  expect(enabledTriggers).toHaveLength(2);
  expect(enabledTriggers).not.toContain('DEFAULT_BRANCH_PIPELINE');
  expect(triggerConfigurations).toEqual({ MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION });
});

it('sends imageSuffix as the GraphQL enum name rather than its backend value', () => {
  const triggers = mapScanProfileVariables({
    scanType: SCAN_TYPE,
    enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
    profileConfiguration: { imageSuffix: '-fips' },
  });

  expect(triggers).toEqual([
    {
      triggerType: 'MERGE_REQUEST_PIPELINE',
      configuration: { secretDetection: { imageSuffix: 'FIPS' } },
    },
  ]);
});

it('translates a GraphQL enum name back to its backend value when reading triggers', () => {
  const { triggerConfigurations } = readScanProfileTriggers([
    {
      triggerType: 'MERGE_REQUEST_PIPELINE',
      configuration: { __typename: 'SecretDetectionConfiguration', imageSuffix: 'FIPS' },
    },
  ]);

  expect(triggerConfigurations).toEqual({ MERGE_REQUEST_PIPELINE: { imageSuffix: '-fips' } });
});

it.each([
  ['differential', 'DIFFERENTIAL'],
  ['false', 'DISABLED'],
])(
  'sends advancedSastPartialScan %p as the GraphQL enum name %p rather than its backend value',
  (backendValue, enumName) => {
    const triggers = mapScanProfileVariables({
      scanType: 'SAST',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
      profileConfiguration: { advancedSastPartialScan: backendValue },
    });

    expect(triggers).toEqual([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: { sast: { advancedSastPartialScan: enumName } },
      },
    ]);
  },
);

it.each([
  ['DIFFERENTIAL', 'differential'],
  ['DISABLED', 'false'],
])(
  'translates the advancedSastPartialScan GraphQL enum name %p back to its backend value %p when reading triggers',
  (enumName, backendValue) => {
    const { triggerConfigurations } = readScanProfileTriggers([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: { __typename: 'SastConfiguration', advancedSastPartialScan: enumName },
      },
    ]);

    expect(triggerConfigurations).toEqual({
      MERGE_REQUEST_PIPELINE: { advancedSastPartialScan: backendValue },
    });
  },
);

describe('dependency scanning', () => {
  it('submits variables under the dependencyScanning key', () => {
    const triggers = mapScanProfileVariables({
      scanType: 'DEPENDENCY_SCANNING',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
      profileConfiguration: { pipIndexUrl: 'https://pypi.example.com/simple' },
    });

    expect(triggers).toEqual([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: { dependencyScanning: { pipIndexUrl: 'https://pypi.example.com/simple' } },
      },
      {
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        configuration: { dependencyScanning: { pipIndexUrl: 'https://pypi.example.com/simple' } },
      },
    ]);
  });

  it('submits integer fields as numbers', () => {
    const triggers = mapScanProfileVariables({
      scanType: 'DEPENDENCY_SCANNING',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
      profileConfiguration: { maxDepth: '-1', apiTimeout: '30', apiScanDownloadDelay: 5 },
    });

    expect(triggers[0].configuration.dependencyScanning).toEqual({
      maxDepth: -1,
      apiTimeout: 30,
      apiScanDownloadDelay: 5,
    });
  });

  it('keeps a non-integer value unchanged', () => {
    const triggers = mapScanProfileVariables({
      scanType: 'DEPENDENCY_SCANNING',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
      profileConfiguration: { maxDepth: 'deep' },
    });

    expect(triggers[0].configuration.dependencyScanning).toEqual({ maxDepth: 'deep' });
  });

  it('removes an emptied integer field', () => {
    const triggers = mapScanProfileVariables({
      scanType: 'DEPENDENCY_SCANNING',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
      profileConfiguration: { maxDepth: '', apiTimeout: '30' },
    });

    expect(triggers[0].configuration.dependencyScanning).toEqual({ apiTimeout: 30 });
  });

  it('submits enum values as GraphQL enum names', () => {
    const triggers = mapScanProfileVariables({
      scanType: 'DEPENDENCY_SCANNING',
      enabledTriggers: ['MERGE_REQUEST_PIPELINE'],
      profileConfiguration: {
        secureLogLevel: 'debug',
        disabledResolutionJobs: ['maven', 'python'],
      },
    });

    expect(triggers[0].configuration.dependencyScanning).toEqual({
      secureLogLevel: 'DEBUG',
      disabledResolutionJobs: ['MAVEN', 'PYTHON'],
    });
  });

  it('reads GraphQL enum names as backend values', () => {
    const { triggerConfigurations } = readScanProfileTriggers([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: {
          __typename: 'DependencyScanningConfiguration',
          secureLogLevel: 'WARN',
          disabledResolutionJobs: ['GRADLE'],
        },
      },
    ]);

    expect(triggerConfigurations).toEqual({
      MERGE_REQUEST_PIPELINE: { secureLogLevel: 'warn', disabledResolutionJobs: ['gradle'] },
    });
  });
});

describe('translateTriggerSettingsFromGraphql', () => {
  it('translates a GraphQL enum name back to its backend value for each trigger', () => {
    const triggerSettings = translateTriggerSettingsFromGraphql([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: { __typename: 'SecretDetectionConfiguration', imageSuffix: 'FIPS' },
      },
      {
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        configuration: { __typename: 'SastConfiguration', advancedSastPartialScan: 'DIFFERENTIAL' },
      },
    ]);

    expect(triggerSettings).toEqual([
      {
        triggerType: 'MERGE_REQUEST_PIPELINE',
        configuration: { __typename: 'SecretDetectionConfiguration', imageSuffix: '-fips' },
      },
      {
        triggerType: 'DEFAULT_BRANCH_PIPELINE',
        configuration: { __typename: 'SastConfiguration', advancedSastPartialScan: 'differential' },
      },
    ]);
  });

  it('leaves a trigger with no configuration untouched', () => {
    const triggerSettings = translateTriggerSettingsFromGraphql([
      { triggerType: 'GIT_PUSH_EVENT', configuration: null },
    ]);

    expect(triggerSettings).toEqual([{ triggerType: 'GIT_PUSH_EVENT', configuration: null }]);
  });

  it('defaults to an empty array when no trigger settings are given', () => {
    expect(translateTriggerSettingsFromGraphql()).toEqual([]);
  });
});

it('creates a profile with its name, description and the same trigger mapping', async () => {
  const input = buildScanProfileCreateInput({
    namespaceId: NAMESPACE_ID,
    scanType: SCAN_TYPE,
    name: 'Nightly secret detection',
    description: 'Scans the default branch overnight',
    enabledTriggers: ALL_TRIGGERS,
    profileConfiguration: PROFILE_CONFIGURATION,
  });

  const { data, handler } = await mutate({
    mutation: securityScanProfileCreateMutation,
    response: createResponse,
    input,
  });
  const { scanProfile } = data.securityScanProfileCreate;
  const { triggerConfigurations } = readScanProfileTriggers(scanProfile.triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      namespaceId: NAMESPACE_ID,
      scanType: SCAN_TYPE,
      name: 'Nightly secret detection',
      description: 'Scans the default branch overnight',
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        {
          triggerType: 'DEFAULT_BRANCH_PIPELINE',
          configuration: { secretDetection: PROFILE_CONFIGURATION },
        },
        { triggerType: 'GIT_PUSH_EVENT' },
      ],
    },
  });
  expect(scanProfile).toMatchObject({
    name: 'Nightly secret detection',
    description: 'Scans the default branch overnight',
    scanType: SCAN_TYPE,
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: PROFILE_CONFIGURATION,
    DEFAULT_BRANCH_PIPELINE: PROFILE_CONFIGURATION,
  });
});

it('submits a SAST profile with per-trigger values', async () => {
  const input = buildScanProfileCreateInput({
    namespaceId: NAMESPACE_ID,
    scanType: 'SAST',
    name: 'Nightly SAST',
    description: 'Scans merge requests for SAST findings',
    enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
    triggerConfigurations: {
      MERGE_REQUEST_PIPELINE: {
        secureAnalyzersPrefix: PREFIX,
        imageSuffix: '-fips',
        analyzerImageTag: '6',
        excludedAnalyzers: ['semgrep'],
        excludedPaths: ['spec/**', 'tmp/**'],
        advancedSastPartialScan: 'differential',
        gitlabAdvSastIncrScan: true,
      },
    },
  });

  const { data, handler } = await mutate({
    mutation: securityScanProfileCreateMutation,
    response: sastCreateResponse,
    input,
  });
  const { scanProfile } = data.securityScanProfileCreate;
  const { triggerConfigurations } = readScanProfileTriggers(scanProfile.triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      namespaceId: NAMESPACE_ID,
      scanType: 'SAST',
      name: 'Nightly SAST',
      description: 'Scans merge requests for SAST findings',
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            sast: {
              secureAnalyzersPrefix: PREFIX,
              imageSuffix: 'FIPS',
              analyzerImageTag: '6',
              excludedAnalyzers: ['semgrep'],
              excludedPaths: ['spec/**', 'tmp/**'],
              advancedSastPartialScan: 'DIFFERENTIAL',
              gitlabAdvSastIncrScan: true,
            },
          },
        },
        { triggerType: 'DEFAULT_BRANCH_PIPELINE' },
      ],
    },
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: {
      secureAnalyzersPrefix: PREFIX,
      imageSuffix: '-fips',
      analyzerImageTag: '6',
      excludedAnalyzers: ['semgrep'],
      excludedPaths: ['spec/**', 'tmp/**'],
      advancedSastPartialScan: 'differential',
      gitlabAdvSastIncrScan: true,
    },
  });
});

it('submits a dependency scanning profile', async () => {
  const input = buildScanProfileCreateInput({
    namespaceId: NAMESPACE_ID,
    scanType: 'DEPENDENCY_SCANNING',
    name: 'Nightly dependency scanning',
    description: 'Scans merge requests for vulnerable dependencies',
    enabledTriggers: ['MERGE_REQUEST_PIPELINE', 'DEFAULT_BRANCH_PIPELINE'],
    triggerConfigurations: {
      MERGE_REQUEST_PIPELINE: {
        secureLogLevel: 'debug',
        maxDepth: '3',
        apiTimeout: '30',
        disabledResolutionJobs: ['maven', 'python'],
        pipExtraIndexUrl: ['https://pypi.example.com/simple'],
        includeDevDependencies: false,
      },
    },
  });

  const { data, handler } = await mutate({
    mutation: securityScanProfileCreateMutation,
    response: dependencyScanningCreateResponse,
    input,
  });
  const { scanProfile } = data.securityScanProfileCreate;
  const { triggerConfigurations } = readScanProfileTriggers(scanProfile.triggerSettings);

  expect(handler).toHaveBeenCalledWith({
    input: {
      namespaceId: NAMESPACE_ID,
      scanType: 'DEPENDENCY_SCANNING',
      name: 'Nightly dependency scanning',
      description: 'Scans merge requests for vulnerable dependencies',
      stripDefaults: false,
      triggers: [
        {
          triggerType: 'MERGE_REQUEST_PIPELINE',
          configuration: {
            dependencyScanning: {
              secureLogLevel: 'DEBUG',
              maxDepth: 3,
              apiTimeout: 30,
              disabledResolutionJobs: ['MAVEN', 'PYTHON'],
              pipExtraIndexUrl: ['https://pypi.example.com/simple'],
              includeDevDependencies: false,
            },
          },
        },
        { triggerType: 'DEFAULT_BRANCH_PIPELINE' },
      ],
    },
  });
  expect(triggerConfigurations).toEqual({
    MERGE_REQUEST_PIPELINE: {
      secureLogLevel: 'debug',
      maxDepth: 3,
      apiTimeout: 30,
      disabledResolutionJobs: ['maven', 'python'],
      pipExtraIndexUrl: ['https://pypi.example.com/simple'],
      includeDevDependencies: false,
    },
  });
});
