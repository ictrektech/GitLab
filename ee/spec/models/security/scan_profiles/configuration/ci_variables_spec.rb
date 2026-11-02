# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::Configuration::CiVariables, feature_category: :security_testing_configuration do
  describe '.build' do
    let(:mappings) do
      {
        test_scan: {
          bool_key: { env: 'TEST_BOOL', type: :boolean },
          string_key: { env: 'TEST_STRING', type: :string },
          array_key: { env: 'TEST_ARRAY', type: :comma_separated_strings }
        }
      }
    end

    before do
      stub_const("#{described_class}::MAPPINGS", mappings)
    end

    it 'serializes each declared type', :aggregate_failures do
      config = { bool_key: true, string_key: 42, array_key: %w[a b c] }

      expect(described_class.build(:test_scan, config)).to eq(
        'TEST_BOOL' => 'true',
        'TEST_STRING' => '42',
        'TEST_ARRAY' => 'a,b,c'
      )
    end

    it 'serializes a false boolean to the string "false"' do
      expect(described_class.build(:test_scan, { bool_key: false })).to eq('TEST_BOOL' => 'false')
    end

    it 'joins a single (non-array) value for the comma_separated_strings type' do
      expect(described_class.build(:test_scan, { array_key: 'solo' })).to eq('TEST_ARRAY' => 'solo')
    end

    it 'resolves both symbol and string config keys', :aggregate_failures do
      expect(described_class.build(:test_scan, { string_key: 'from_symbol' })).to eq('TEST_STRING' => 'from_symbol')
      expect(described_class.build(:test_scan, { 'string_key' => 'from_string' })).to eq('TEST_STRING' => 'from_string')
    end

    it 'returns an empty hash for an unknown scan type' do
      expect(described_class.build(:unknown_scan, { string_key: 'x' })).to eq({})
    end

    it 'returns an empty hash for a nil scan type' do
      expect(described_class.build(nil, { string_key: 'x' })).to eq({})
    end

    it 'returns an empty hash for a nil config' do
      expect(described_class.build(:test_scan, nil)).to eq({})
    end

    it 'returns an empty hash for a nil value in a config' do
      expect(described_class.build(:test_scan, { bool_key: nil })).to eq({})
    end
  end

  describe 'secret_detection mapping' do
    it 'maps each configured value to its environment variable', :aggregate_failures do
      config = {
        secure_analyzers_prefix: 'registry.example.com',
        image_suffix: '-fips',
        historic_scan: true,
        log_options: 'abc..def',
        excluded_paths: %w[spec tmp],
        ruleset_git_reference: 'refs/heads/main'
      }

      expect(described_class.build(:secret_detection, config)).to eq(
        'SECURE_ANALYZERS_PREFIX' => 'registry.example.com',
        'SECRET_DETECTION_IMAGE_SUFFIX' => '-fips',
        'SECRET_DETECTION_HISTORIC_SCAN' => 'true',
        'SECRET_DETECTION_LOG_OPTIONS' => 'abc..def',
        'SECRET_DETECTION_EXCLUDED_PATHS' => 'spec,tmp',
        'SECRET_DETECTION_RULESET_GIT_REFERENCE' => 'refs/heads/main'
      )
    end
  end

  describe 'sast mapping' do
    it 'maps each configured value to its environment variable', :aggregate_failures do
      config = {
        secure_analyzers_prefix: 'registry.example.com',
        image_suffix: '-fips',
        analyzer_image_tag: '5',
        excluded_analyzers: %w[semgrep-sast pmd-apex],
        excluded_paths: %w[spec tmp],
        advanced_sast_partial_scan: 'differential',
        gitlab_adv_sast_incr_scan: true
      }

      expect(described_class.build(:sast, config)).to eq(
        'SECURE_ANALYZERS_PREFIX' => 'registry.example.com',
        'SAST_IMAGE_SUFFIX' => '-fips',
        'SAST_ANALYZER_IMAGE_TAG' => '5',
        'SAST_EXCLUDED_ANALYZERS' => 'semgrep-sast,pmd-apex',
        'SAST_EXCLUDED_PATHS' => 'spec,tmp',
        'ADVANCED_SAST_PARTIAL_SCAN' => 'differential',
        'GITLAB_ADV_SAST_INCR_SCAN' => 'true'
      )
    end
  end

  describe 'dependency_scanning mapping' do
    it 'maps each configured value to its environment variable', :aggregate_failures do
      config = {
        secure_analyzers_prefix: 'registry.example.com',
        additional_ca_cert_bundle: '-----BEGIN CERTIFICATE-----',
        secure_log_level: 'debug',
        excluded_paths: %w[spec tmp],
        include_dev_dependencies: false,
        max_depth: -1,
        pip_dependency_path: 'vendor/python',
        static_reachability_enabled: true,
        enable_manifest_fallback: false,
        pipcompile_lockfile_file_name_pattern: '*.lock',
        pip_manifest_file_name_pattern: 'requirements*.txt',
        enable_vulnerability_scan: false,
        api_timeout: 20,
        api_scan_download_delay: 5,
        maven_dependency_plugin_version: '3.7.0',
        maven_args: '-DskipTests',
        gradle_cli_opts: '--offline',
        disabled_resolution_jobs: %w[maven python],
        maven_resolution_image: 'registry.example.com/maven:1',
        gradle_resolution_image: 'registry.example.com/gradle:1',
        python_resolution_image: 'registry.example.com/python:1',
        pip_index_url: 'https://pypi.example.com/simple',
        pip_extra_index_url: %w[https://a.example.com https://b.example.com],
        search_ignore_hidden_dirs: true
      }

      expect(described_class.build(:dependency_scanning, config)).to eq(
        'SECURE_ANALYZERS_PREFIX' => 'registry.example.com',
        'ADDITIONAL_CA_CERT_BUNDLE' => '-----BEGIN CERTIFICATE-----',
        'SECURE_LOG_LEVEL' => 'debug',
        'DS_EXCLUDED_PATHS' => 'spec,tmp',
        'DS_INCLUDE_DEV_DEPENDENCIES' => 'false',
        'DS_MAX_DEPTH' => '-1',
        'DS_PIP_DEPENDENCY_PATH' => 'vendor/python',
        'DS_STATIC_REACHABILITY_ENABLED' => 'true',
        'DS_ENABLE_MANIFEST_FALLBACK' => 'false',
        'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN' => '*.lock',
        'DS_PIP_MANIFEST_FILE_NAME_PATTERN' => 'requirements*.txt',
        'DS_ENABLE_VULNERABILITY_SCAN' => 'false',
        'DS_API_TIMEOUT' => '20',
        'DS_API_SCAN_DOWNLOAD_DELAY' => '5',
        'DS_MAVEN_DEPENDENCY_PLUGIN_VERSION' => '3.7.0',
        'MAVEN_ARGS' => '-DskipTests',
        'GRADLE_CLI_OPTS' => '--offline',
        'DS_DISABLED_RESOLUTION_JOBS' => 'maven,python',
        'DS_MAVEN_RESOLUTION_IMAGE' => 'registry.example.com/maven:1',
        'DS_GRADLE_RESOLUTION_IMAGE' => 'registry.example.com/gradle:1',
        'DS_PYTHON_RESOLUTION_IMAGE' => 'registry.example.com/python:1',
        'PIP_INDEX_URL' => 'https://pypi.example.com/simple',
        'PIP_EXTRA_INDEX_URL' => 'https://a.example.com https://b.example.com',
        'SEARCH_IGNORE_HIDDEN_DIRS' => 'true'
      )
    end
  end
end
