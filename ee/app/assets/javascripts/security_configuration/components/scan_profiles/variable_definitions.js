import { s__ } from '~/locale';
import {
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

export const VALUE_TYPE_BOOLEAN = 'boolean';
export const VALUE_TYPE_ENUM = 'enum';
export const VALUE_TYPE_MULTI_SELECT = 'multiSelect';
export const VALUE_TYPE_NUMBER = 'number';
export const VALUE_TYPE_STRING = 'string';
export const VALUE_TYPE_STRING_LIST = 'stringList';

// envVar mirrors Security::ScanProfiles::Configuration::CiVariables::MAPPINGS in
// ee/app/models/security/scan_profiles/configuration/ci_variables.rb, the source of truth for
// which CI/CD variable each field becomes. Only secureAnalyzersPrefix is shared between scan
// types there; imageSuffix and excludedPaths use a different variable name per scan type even
// though the GraphQL field and UI copy are otherwise identical.
const IMAGE_SUFFIX_OPTIONS = [
  { value: '', text: s__('ScanProfiles|Default') },
  // eslint-disable-next-line @gitlab/require-i18n-strings -- backend suffix value, not prose
  { value: '-fips', text: s__('ScanProfiles|FIPS') },
];

const secureAnalyzersPrefix = {
  label: s__('ScanProfiles|Analyzer image registry'),
  description: s__(
    "ScanProfiles|Pull analyzer images from your own container registry instead of GitLab's public one.",
  ),
  valueType: VALUE_TYPE_STRING,
  placeholder: 'registry.example.com/analyzers',
  envVar: 'SECURE_ANALYZERS_PREFIX',
};

const imageSuffix = (envVar) => ({
  label: s__('ScanProfiles|Image variant'),
  description: s__('ScanProfiles|Which build of the analyzer image to pull.'),
  valueType: VALUE_TYPE_ENUM,
  options: IMAGE_SUFFIX_OPTIONS,
  envVar,
});

const excludedPaths = (envVar) => ({
  label: s__('ScanProfiles|Paths to exclude'),
  description: s__('ScanProfiles|Paths left out of the scan.'),
  valueType: VALUE_TYPE_STRING_LIST,
  placeholder: 'spec/**',
  envVar,
});

// Mirrors SecretDetectionConfigurationInputType in
// ee/app/graphql/types/security/scan_profiles/secret_detection_configuration_input_type.rb
const SECRET_DETECTION_VARIABLE_DEFINITIONS = {
  secureAnalyzersPrefix,
  imageSuffix: imageSuffix('SECRET_DETECTION_IMAGE_SUFFIX'),
  historicScan: {
    label: s__('ScanProfiles|Historic scan'),
    description: s__('ScanProfiles|Scan the full Git history instead of only the current state.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'SECRET_DETECTION_HISTORIC_SCAN',
  },
  logOptions: {
    label: s__('ScanProfiles|Log options'),
    description: s__('ScanProfiles|Options passed to git log to control the commit range scanned.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: '--since=1.year.ago',
    envVar: 'SECRET_DETECTION_LOG_OPTIONS',
  },
  excludedPaths: excludedPaths('SECRET_DETECTION_EXCLUDED_PATHS'),
  rulesetGitReference: {
    label: s__('ScanProfiles|Ruleset Git reference'),
    description: s__('ScanProfiles|Git reference of the remote ruleset configuration to use.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'gitlab.com/example-group/remote-ruleset-project',
    envVar: 'SECRET_DETECTION_RULESET_GIT_REFERENCE',
  },
};

// Mirrors SastConfigurationInputType in
// ee/app/graphql/types/security/scan_profiles/sast_configuration_input_type.rb
const SAST_VARIABLE_DEFINITIONS = {
  secureAnalyzersPrefix,
  imageSuffix: imageSuffix('SAST_IMAGE_SUFFIX'),
  analyzerImageTag: {
    label: s__('ScanProfiles|Analyzer image tag'),
    description: s__('ScanProfiles|Pin the analyzer image to a specific tag.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: '3.7',
    envVar: 'SAST_ANALYZER_IMAGE_TAG',
  },
  excludedAnalyzers: {
    label: s__('ScanProfiles|Analyzers to skip'),
    description: s__('ScanProfiles|Analyzers that should not run for this profile.'),
    valueType: VALUE_TYPE_STRING_LIST,
    placeholder: 'semgrep',
    envVar: 'SAST_EXCLUDED_ANALYZERS',
  },
  excludedPaths: excludedPaths('SAST_EXCLUDED_PATHS'),
  advancedSastPartialScan: {
    label: s__('ScanProfiles|Advanced SAST partial scanning'),
    description: s__('ScanProfiles|Controls GitLab Advanced SAST diff-based scanning.'),
    valueType: VALUE_TYPE_ENUM,
    options: [
      { value: 'differential', text: s__('ScanProfiles|Enabled') },
      { value: 'false', text: s__('ScanProfiles|Disabled') },
    ],
    envVar: 'ADVANCED_SAST_PARTIAL_SCAN',
  },
  gitlabAdvSastIncrScan: {
    label: s__('ScanProfiles|Advanced SAST incremental scanning'),
    description: s__('ScanProfiles|Whether GitLab Advanced SAST incremental scanning is enabled.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'GITLAB_ADV_SAST_INCR_SCAN',
  },
};

// Mirrors DependencyScanningConfigurationInputType in
// ee/app/graphql/types/security/scan_profiles/dependency_scanning_configuration_input_type.rb
const DEPENDENCY_SCANNING_VARIABLE_DEFINITIONS = {
  secureAnalyzersPrefix,
  additionalCaCertBundle: {
    label: s__('ScanProfiles|CA certificate bundle'),
    description: s__('ScanProfiles|CA certificate bundle to trust during the scan.'),
    valueType: VALUE_TYPE_STRING,
    // eslint-disable-next-line @gitlab/require-i18n-strings
    placeholder: '-----BEGIN CERTIFICATE-----',
    envVar: 'ADDITIONAL_CA_CERT_BUNDLE',
  },
  secureLogLevel: {
    label: s__('ScanProfiles|Log level'),
    description: s__('ScanProfiles|Logging level used by the analyzer.'),
    valueType: VALUE_TYPE_ENUM,
    options: [
      { value: 'fatal', text: s__('ScanProfiles|Fatal') },
      { value: 'error', text: s__('ScanProfiles|Error') },
      { value: 'warn', text: s__('ScanProfiles|Warning') },
      { value: 'info', text: s__('ScanProfiles|Info') },
      { value: 'debug', text: s__('ScanProfiles|Debug') },
    ],
    envVar: 'SECURE_LOG_LEVEL',
  },
  excludedPaths: excludedPaths('DS_EXCLUDED_PATHS'),
  includeDevDependencies: {
    label: s__('ScanProfiles|Include development dependencies'),
    description: s__('ScanProfiles|Include development and test dependencies in the scan.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'DS_INCLUDE_DEV_DEPENDENCIES',
  },
  maxDepth: {
    label: s__('ScanProfiles|Maximum directory depth'),
    description: s__('ScanProfiles|Directory depth the analyzer scans. -1 scans all directories.'),
    valueType: VALUE_TYPE_NUMBER,
    min: -1,
    placeholder: '2',
    envVar: 'DS_MAX_DEPTH',
  },
  pipDependencyPath: {
    label: s__('ScanProfiles|pip dependency path'),
    description: s__('ScanProfiles|Path to install Python packages for analysis.'),
    valueType: VALUE_TYPE_STRING,
    // eslint-disable-next-line @gitlab/no-hardcoded-urls
    placeholder: '/pip-cache',
    envVar: 'DS_PIP_DEPENDENCY_PATH',
  },
  staticReachabilityEnabled: {
    label: s__('ScanProfiles|Static reachability'),
    description: s__('ScanProfiles|Whether static reachability is enabled.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'DS_STATIC_REACHABILITY_ENABLED',
  },
  enableManifestFallback: {
    label: s__('ScanProfiles|Manifest fallback'),
    description: s__('ScanProfiles|Whether manifest fallback is enabled.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'DS_ENABLE_MANIFEST_FALLBACK',
  },
  pipcompileLockfileFileNamePattern: {
    label: s__('ScanProfiles|pip-compile lockfile name pattern'),
    description: s__('ScanProfiles|File name pattern of pip-compile lockfiles to analyze.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'requirements*.txt',
    envVar: 'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN',
  },
  pipManifestFileNamePattern: {
    label: s__('ScanProfiles|pip manifest name pattern'),
    description: s__('ScanProfiles|File name pattern of pip manifests to resolve and scan.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'requirements*.txt',
    envVar: 'DS_PIP_MANIFEST_FILE_NAME_PATTERN',
  },
  enableVulnerabilityScan: {
    label: s__('ScanProfiles|Vulnerability scan'),
    description: s__('ScanProfiles|Whether generated SBOMs are analyzed for vulnerabilities.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'DS_ENABLE_VULNERABILITY_SCAN',
  },
  apiTimeout: {
    label: s__('ScanProfiles|API timeout'),
    description: s__('ScanProfiles|Vulnerability scanning API timeout in seconds, from 5 to 300.'),
    valueType: VALUE_TYPE_NUMBER,
    min: 5,
    max: 300,
    placeholder: '10',
    envVar: 'DS_API_TIMEOUT',
  },
  apiScanDownloadDelay: {
    label: s__('ScanProfiles|API download delay'),
    description: s__(
      'ScanProfiles|Seconds to wait before downloading vulnerability scan results, from 1 to 120.',
    ),
    valueType: VALUE_TYPE_NUMBER,
    min: 1,
    max: 120,
    placeholder: '3',
    envVar: 'DS_API_SCAN_DOWNLOAD_DELAY',
  },
  mavenDependencyPluginVersion: {
    label: s__('ScanProfiles|maven-dependency-plugin version'),
    description: s__('ScanProfiles|Version of maven-dependency-plugin used during resolution.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: '3.8.1',
    envVar: 'DS_MAVEN_DEPENDENCY_PLUGIN_VERSION',
  },
  mavenArgs: {
    label: s__('ScanProfiles|Maven arguments'),
    description: s__('ScanProfiles|Additional arguments passed to Maven during resolution.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: '--settings ci_settings.xml',
    envVar: 'MAVEN_ARGS',
  },
  gradleCliOpts: {
    label: s__('ScanProfiles|Gradle options'),
    description: s__(
      'ScanProfiles|Additional command-line options passed to Gradle during resolution.',
    ),
    valueType: VALUE_TYPE_STRING,
    placeholder: '-Dhttps.proxyHost=proxy.example.com',
    envVar: 'GRADLE_CLI_OPTS',
  },
  disabledResolutionJobs: {
    label: s__('ScanProfiles|Resolution jobs to skip'),
    description: s__('ScanProfiles|Dependency resolution jobs that should not run.'),
    valueType: VALUE_TYPE_MULTI_SELECT,
    options: [
      { value: 'maven', text: s__('ScanProfiles|Maven') },
      { value: 'gradle', text: s__('ScanProfiles|Gradle') },
      { value: 'python', text: s__('ScanProfiles|Python') },
    ],
    placeholder: s__('ScanProfiles|Select jobs to skip'),
    envVar: 'DS_DISABLED_RESOLUTION_JOBS',
  },
  mavenResolutionImage: {
    label: s__('ScanProfiles|Maven resolution image'),
    description: s__('ScanProfiles|Image used by the Maven dependency resolution job.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'registry.example.com/maven:3.9',
    envVar: 'DS_MAVEN_RESOLUTION_IMAGE',
  },
  gradleResolutionImage: {
    label: s__('ScanProfiles|Gradle resolution image'),
    description: s__('ScanProfiles|Image used by the Gradle dependency resolution job.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'registry.example.com/gradle:8',
    envVar: 'DS_GRADLE_RESOLUTION_IMAGE',
  },
  pythonResolutionImage: {
    label: s__('ScanProfiles|Python resolution image'),
    description: s__('ScanProfiles|Image used by the Python dependency resolution job.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'registry.example.com/python:3.12',
    envVar: 'DS_PYTHON_RESOLUTION_IMAGE',
  },
  pipIndexUrl: {
    label: s__('ScanProfiles|pip index URL'),
    description: s__('ScanProfiles|Base URL of the Python Package Index.'),
    valueType: VALUE_TYPE_STRING,
    placeholder: 'https://pypi.example.com/simple',
    envVar: 'PIP_INDEX_URL',
  },
  pipExtraIndexUrl: {
    label: s__('ScanProfiles|pip extra index URLs'),
    description: s__('ScanProfiles|Additional Python package indexes to use.'),
    valueType: VALUE_TYPE_STRING_LIST,
    placeholder: 'https://pypi.example.com/simple',
    envVar: 'PIP_EXTRA_INDEX_URL',
  },
  searchIgnoreHiddenDirs: {
    label: s__('ScanProfiles|Ignore hidden directories'),
    description: s__('ScanProfiles|Skip hidden directories when searching for supported files.'),
    valueType: VALUE_TYPE_BOOLEAN,
    envVar: 'SEARCH_IGNORE_HIDDEN_DIRS',
  },
};

const VARIABLE_DEFINITIONS_BY_SCAN_TYPE = {
  [SCAN_PROFILE_TYPE_SECRET_DETECTION]: SECRET_DETECTION_VARIABLE_DEFINITIONS,
  [SCAN_PROFILE_TYPE_SAST]: SAST_VARIABLE_DEFINITIONS,
  [SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING]: DEPENDENCY_SCANNING_VARIABLE_DEFINITIONS,
};

export const variableDefinitionsFor = (scanType) =>
  VARIABLE_DEFINITIONS_BY_SCAN_TYPE[scanType] ?? {};
