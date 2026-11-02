import {
  variableDefinitionsFor,
  VALUE_TYPE_BOOLEAN,
  VALUE_TYPE_ENUM,
  VALUE_TYPE_MULTI_SELECT,
  VALUE_TYPE_NUMBER,
  VALUE_TYPE_STRING,
  VALUE_TYPE_STRING_LIST,
} from 'ee/security_configuration/components/scan_profiles/variable_definitions';
import {
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
} from '~/security_configuration/constants';

describe('variable_definitions', () => {
  describe('variableDefinitionsFor', () => {
    it('returns an empty object for an unknown scan type', () => {
      expect(variableDefinitionsFor('NOT_A_SCANNER')).toEqual({});
    });

    describe('Secret Detection', () => {
      const definitions = variableDefinitionsFor(SCAN_PROFILE_TYPE_SECRET_DETECTION);

      // Mirrors SecretDetectionConfigurationInputType in
      // ee/app/graphql/types/security/scan_profiles/secret_detection_configuration_input_type.rb
      it('exposes exactly the fields the input type accepts', () => {
        expect(Object.keys(definitions).sort()).toEqual(
          [
            'secureAnalyzersPrefix',
            'imageSuffix',
            'historicScan',
            'logOptions',
            'excludedPaths',
            'rulesetGitReference',
          ].sort(),
        );
      });

      // Mirrors Security::ScanProfiles::Configuration::CiVariables::MAPPINGS[:secret_detection]
      // in ee/app/models/security/scan_profiles/configuration/ci_variables.rb
      it.each`
        setting                    | envVar                                      | valueType
        ${'secureAnalyzersPrefix'} | ${'SECURE_ANALYZERS_PREFIX'}                | ${VALUE_TYPE_STRING}
        ${'imageSuffix'}           | ${'SECRET_DETECTION_IMAGE_SUFFIX'}          | ${VALUE_TYPE_ENUM}
        ${'historicScan'}          | ${'SECRET_DETECTION_HISTORIC_SCAN'}         | ${VALUE_TYPE_BOOLEAN}
        ${'logOptions'}            | ${'SECRET_DETECTION_LOG_OPTIONS'}           | ${VALUE_TYPE_STRING}
        ${'excludedPaths'}         | ${'SECRET_DETECTION_EXCLUDED_PATHS'}        | ${VALUE_TYPE_STRING_LIST}
        ${'rulesetGitReference'}   | ${'SECRET_DETECTION_RULESET_GIT_REFERENCE'} | ${VALUE_TYPE_STRING}
      `('maps $setting to $envVar as a $valueType', ({ setting, envVar, valueType }) => {
        expect(definitions[setting]).toMatchObject({ envVar, valueType });
        expect(definitions[setting].label).toEqual(expect.any(String));
        expect(definitions[setting].description).toEqual(expect.any(String));
      });

      it('uses a project path as the rulesetGitReference placeholder', () => {
        expect(definitions.rulesetGitReference.placeholder).toBe(
          'gitlab.com/example-group/remote-ruleset-project',
        );
      });

      it('offers Default and FIPS as the imageSuffix options', () => {
        expect(definitions.imageSuffix.options).toEqual([
          { value: '', text: expect.any(String) },
          { value: '-fips', text: expect.any(String) },
        ]);
      });
    });

    describe('SAST', () => {
      const definitions = variableDefinitionsFor(SCAN_PROFILE_TYPE_SAST);

      // Mirrors SastConfigurationInputType in
      // ee/app/graphql/types/security/scan_profiles/sast_configuration_input_type.rb
      it('exposes exactly the fields the input type accepts', () => {
        expect(Object.keys(definitions).sort()).toEqual(
          [
            'secureAnalyzersPrefix',
            'imageSuffix',
            'analyzerImageTag',
            'excludedAnalyzers',
            'excludedPaths',
            'advancedSastPartialScan',
            'gitlabAdvSastIncrScan',
          ].sort(),
        );
      });

      // Mirrors Security::ScanProfiles::Configuration::CiVariables::MAPPINGS[:sast] in
      // ee/app/models/security/scan_profiles/configuration/ci_variables.rb
      it.each`
        setting                      | envVar                          | valueType
        ${'secureAnalyzersPrefix'}   | ${'SECURE_ANALYZERS_PREFIX'}    | ${VALUE_TYPE_STRING}
        ${'imageSuffix'}             | ${'SAST_IMAGE_SUFFIX'}          | ${VALUE_TYPE_ENUM}
        ${'analyzerImageTag'}        | ${'SAST_ANALYZER_IMAGE_TAG'}    | ${VALUE_TYPE_STRING}
        ${'excludedAnalyzers'}       | ${'SAST_EXCLUDED_ANALYZERS'}    | ${VALUE_TYPE_STRING_LIST}
        ${'excludedPaths'}           | ${'SAST_EXCLUDED_PATHS'}        | ${VALUE_TYPE_STRING_LIST}
        ${'advancedSastPartialScan'} | ${'ADVANCED_SAST_PARTIAL_SCAN'} | ${VALUE_TYPE_ENUM}
        ${'gitlabAdvSastIncrScan'}   | ${'GITLAB_ADV_SAST_INCR_SCAN'}  | ${VALUE_TYPE_BOOLEAN}
      `('maps $setting to $envVar as a $valueType', ({ setting, envVar, valueType }) => {
        expect(definitions[setting]).toMatchObject({ envVar, valueType });
        expect(definitions[setting].label).toEqual(expect.any(String));
        expect(definitions[setting].description).toEqual(expect.any(String));
      });

      it('uses a bare version as the analyzerImageTag placeholder', () => {
        expect(definitions.analyzerImageTag.placeholder).toBe('3.7');
      });

      it('offers differential/false as the advancedSastPartialScan options', () => {
        expect(definitions.advancedSastPartialScan.options).toEqual([
          { value: 'differential', text: expect.any(String) },
          { value: 'false', text: expect.any(String) },
        ]);
      });
    });

    describe('Dependency Scanning', () => {
      const definitions = variableDefinitionsFor(SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING);

      it.each`
        setting                                | envVar                                        | valueType
        ${'secureAnalyzersPrefix'}             | ${'SECURE_ANALYZERS_PREFIX'}                  | ${VALUE_TYPE_STRING}
        ${'additionalCaCertBundle'}            | ${'ADDITIONAL_CA_CERT_BUNDLE'}                | ${VALUE_TYPE_STRING}
        ${'secureLogLevel'}                    | ${'SECURE_LOG_LEVEL'}                         | ${VALUE_TYPE_ENUM}
        ${'excludedPaths'}                     | ${'DS_EXCLUDED_PATHS'}                        | ${VALUE_TYPE_STRING_LIST}
        ${'includeDevDependencies'}            | ${'DS_INCLUDE_DEV_DEPENDENCIES'}              | ${VALUE_TYPE_BOOLEAN}
        ${'maxDepth'}                          | ${'DS_MAX_DEPTH'}                             | ${VALUE_TYPE_NUMBER}
        ${'pipDependencyPath'}                 | ${'DS_PIP_DEPENDENCY_PATH'}                   | ${VALUE_TYPE_STRING}
        ${'staticReachabilityEnabled'}         | ${'DS_STATIC_REACHABILITY_ENABLED'}           | ${VALUE_TYPE_BOOLEAN}
        ${'enableManifestFallback'}            | ${'DS_ENABLE_MANIFEST_FALLBACK'}              | ${VALUE_TYPE_BOOLEAN}
        ${'pipcompileLockfileFileNamePattern'} | ${'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN'} | ${VALUE_TYPE_STRING}
        ${'pipManifestFileNamePattern'}        | ${'DS_PIP_MANIFEST_FILE_NAME_PATTERN'}        | ${VALUE_TYPE_STRING}
        ${'enableVulnerabilityScan'}           | ${'DS_ENABLE_VULNERABILITY_SCAN'}             | ${VALUE_TYPE_BOOLEAN}
        ${'apiTimeout'}                        | ${'DS_API_TIMEOUT'}                           | ${VALUE_TYPE_NUMBER}
        ${'apiScanDownloadDelay'}              | ${'DS_API_SCAN_DOWNLOAD_DELAY'}               | ${VALUE_TYPE_NUMBER}
        ${'mavenDependencyPluginVersion'}      | ${'DS_MAVEN_DEPENDENCY_PLUGIN_VERSION'}       | ${VALUE_TYPE_STRING}
        ${'mavenArgs'}                         | ${'MAVEN_ARGS'}                               | ${VALUE_TYPE_STRING}
        ${'gradleCliOpts'}                     | ${'GRADLE_CLI_OPTS'}                          | ${VALUE_TYPE_STRING}
        ${'disabledResolutionJobs'}            | ${'DS_DISABLED_RESOLUTION_JOBS'}              | ${VALUE_TYPE_MULTI_SELECT}
        ${'mavenResolutionImage'}              | ${'DS_MAVEN_RESOLUTION_IMAGE'}                | ${VALUE_TYPE_STRING}
        ${'gradleResolutionImage'}             | ${'DS_GRADLE_RESOLUTION_IMAGE'}               | ${VALUE_TYPE_STRING}
        ${'pythonResolutionImage'}             | ${'DS_PYTHON_RESOLUTION_IMAGE'}               | ${VALUE_TYPE_STRING}
        ${'pipIndexUrl'}                       | ${'PIP_INDEX_URL'}                            | ${VALUE_TYPE_STRING}
        ${'pipExtraIndexUrl'}                  | ${'PIP_EXTRA_INDEX_URL'}                      | ${VALUE_TYPE_STRING_LIST}
        ${'searchIgnoreHiddenDirs'}            | ${'SEARCH_IGNORE_HIDDEN_DIRS'}                | ${VALUE_TYPE_BOOLEAN}
      `('maps $setting to $envVar as a $valueType', ({ setting, envVar, valueType }) => {
        expect(definitions[setting]).toMatchObject({ envVar, valueType });
        expect(definitions[setting].label).toEqual(expect.any(String));
        expect(definitions[setting].description).toEqual(expect.any(String));
      });

      it('returns one definition per input type field', () => {
        expect(Object.keys(definitions)).toHaveLength(24);
      });

      it('returns the log levels as secureLogLevel options', () => {
        expect(definitions.secureLogLevel.options.map(({ value }) => value)).toEqual([
          'fatal',
          'error',
          'warn',
          'info',
          'debug',
        ]);
      });

      it.each`
        setting                   | min   | max
        ${'maxDepth'}             | ${-1} | ${undefined}
        ${'apiTimeout'}           | ${5}  | ${300}
        ${'apiScanDownloadDelay'} | ${1}  | ${120}
      `('returns the $setting range', ({ setting, min, max }) => {
        expect(definitions[setting].min).toBe(min);
        expect(definitions[setting].max).toBe(max);
      });

      it('returns the disabledResolutionJobs options', () => {
        expect(definitions.disabledResolutionJobs.options.map(({ value }) => value)).toEqual([
          'maven',
          'gradle',
          'python',
        ]);
      });
    });

    it('uses the same env var and options for secureAnalyzersPrefix and imageSuffix options in both scan types', () => {
      const secretDetection = variableDefinitionsFor(SCAN_PROFILE_TYPE_SECRET_DETECTION);
      const sast = variableDefinitionsFor(SCAN_PROFILE_TYPE_SAST);

      expect(secretDetection.secureAnalyzersPrefix.envVar).toBe(sast.secureAnalyzersPrefix.envVar);
      expect(secretDetection.imageSuffix.options).toEqual(sast.imageSuffix.options);
    });

    it('gives imageSuffix and excludedPaths a different env var per scan type', () => {
      const secretDetection = variableDefinitionsFor(SCAN_PROFILE_TYPE_SECRET_DETECTION);
      const sast = variableDefinitionsFor(SCAN_PROFILE_TYPE_SAST);

      expect(secretDetection.imageSuffix.envVar).not.toBe(sast.imageSuffix.envVar);
      expect(secretDetection.excludedPaths.envVar).not.toBe(sast.excludedPaths.envVar);
    });
  });
});
