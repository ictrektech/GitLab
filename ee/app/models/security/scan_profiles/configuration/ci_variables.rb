# frozen_string_literal: true

module Security
  module ScanProfiles
    class Configuration
      module CiVariables
        SERIALIZERS = {
          boolean: ->(value) { value ? 'true' : 'false' },
          string: ->(value) { value.to_s },
          comma_separated_strings: ->(value) { Array(value).join(',') },
          space_separated_strings: ->(value) { Array(value).join(' ') }
        }.freeze

        # rubocop:disable Layout/HashAlignment -- aligned as a table for readability where the 120-char
        # line limit allows; dependency_scanning has keys and env names too long to align.
        MAPPINGS = {
          secret_detection: {
            secure_analyzers_prefix: { env: 'SECURE_ANALYZERS_PREFIX',                type: :string },
            image_suffix:            { env: 'SECRET_DETECTION_IMAGE_SUFFIX',          type: :string },
            historic_scan:           { env: 'SECRET_DETECTION_HISTORIC_SCAN',         type: :boolean },
            log_options:             { env: 'SECRET_DETECTION_LOG_OPTIONS',           type: :string },
            excluded_paths:          { env: 'SECRET_DETECTION_EXCLUDED_PATHS',        type: :comma_separated_strings },
            ruleset_git_reference:   { env: 'SECRET_DETECTION_RULESET_GIT_REFERENCE', type: :string }
          },
          sast: {
            secure_analyzers_prefix:    { env: 'SECURE_ANALYZERS_PREFIX',    type: :string },
            image_suffix:               { env: 'SAST_IMAGE_SUFFIX',          type: :string },
            analyzer_image_tag:         { env: 'SAST_ANALYZER_IMAGE_TAG',    type: :string },
            excluded_analyzers:         { env: 'SAST_EXCLUDED_ANALYZERS',    type: :comma_separated_strings },
            excluded_paths:             { env: 'SAST_EXCLUDED_PATHS',        type: :comma_separated_strings },
            advanced_sast_partial_scan: { env: 'ADVANCED_SAST_PARTIAL_SCAN', type: :string },
            gitlab_adv_sast_incr_scan:  { env: 'GITLAB_ADV_SAST_INCR_SCAN',  type: :boolean }
          },
          dependency_scanning: {
            secure_analyzers_prefix: { env: 'SECURE_ANALYZERS_PREFIX', type: :string },
            additional_ca_cert_bundle: { env: 'ADDITIONAL_CA_CERT_BUNDLE', type: :string },
            secure_log_level: { env: 'SECURE_LOG_LEVEL', type: :string },
            excluded_paths: { env: 'DS_EXCLUDED_PATHS', type: :comma_separated_strings },
            include_dev_dependencies: { env: 'DS_INCLUDE_DEV_DEPENDENCIES', type: :boolean },
            max_depth: { env: 'DS_MAX_DEPTH', type: :string },
            pip_dependency_path: { env: 'DS_PIP_DEPENDENCY_PATH', type: :string },
            static_reachability_enabled: { env: 'DS_STATIC_REACHABILITY_ENABLED', type: :boolean },
            enable_manifest_fallback: { env: 'DS_ENABLE_MANIFEST_FALLBACK', type: :boolean },
            pipcompile_lockfile_file_name_pattern: { env: 'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN', type: :string },
            pip_manifest_file_name_pattern: { env: 'DS_PIP_MANIFEST_FILE_NAME_PATTERN', type: :string },
            enable_vulnerability_scan: { env: 'DS_ENABLE_VULNERABILITY_SCAN', type: :boolean },
            api_timeout: { env: 'DS_API_TIMEOUT', type: :string },
            api_scan_download_delay: { env: 'DS_API_SCAN_DOWNLOAD_DELAY', type: :string },
            maven_dependency_plugin_version: { env: 'DS_MAVEN_DEPENDENCY_PLUGIN_VERSION', type: :string },
            maven_args: { env: 'MAVEN_ARGS', type: :string },
            gradle_cli_opts: { env: 'GRADLE_CLI_OPTS', type: :string },
            disabled_resolution_jobs: { env: 'DS_DISABLED_RESOLUTION_JOBS', type: :comma_separated_strings },
            maven_resolution_image: { env: 'DS_MAVEN_RESOLUTION_IMAGE', type: :string },
            gradle_resolution_image: { env: 'DS_GRADLE_RESOLUTION_IMAGE', type: :string },
            python_resolution_image: { env: 'DS_PYTHON_RESOLUTION_IMAGE', type: :string },
            pip_index_url: { env: 'PIP_INDEX_URL', type: :string },
            # pip splits PIP_EXTRA_INDEX_URL on whitespace, so a comma-joined list reads as one URL.
            pip_extra_index_url: { env: 'PIP_EXTRA_INDEX_URL', type: :space_separated_strings },
            search_ignore_hidden_dirs: { env: 'SEARCH_IGNORE_HIDDEN_DIRS', type: :boolean }
          }
        }.freeze
        # rubocop:enable Layout/HashAlignment

        def self.build(scan_type, config)
          symbolized = config.to_h.deep_symbolize_keys

          MAPPINGS.fetch(scan_type&.to_sym, {}).each_with_object({}) do |(key, definition), variables|
            next if symbolized[key].nil?

            variables[definition[:env]] = SERIALIZERS.fetch(definition[:type]).call(symbolized[key])
          end
        end
      end
    end
  end
end
