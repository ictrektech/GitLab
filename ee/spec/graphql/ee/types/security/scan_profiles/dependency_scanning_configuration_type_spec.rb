# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::DependencyScanningConfigurationType, feature_category: :security_testing_configuration do
  it { expect(described_class.graphql_name).to eq('DependencyScanningConfiguration') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(
      :secure_analyzers_prefix,
      :additional_ca_cert_bundle,
      :secure_log_level,
      :excluded_paths,
      :include_dev_dependencies,
      :max_depth,
      :pip_dependency_path,
      :static_reachability_enabled,
      :enable_manifest_fallback,
      :pipcompile_lockfile_file_name_pattern,
      :pip_manifest_file_name_pattern,
      :enable_vulnerability_scan,
      :api_timeout,
      :api_scan_download_delay,
      :maven_dependency_plugin_version,
      :maven_args,
      :gradle_cli_opts,
      :disabled_resolution_jobs,
      :maven_resolution_image,
      :gradle_resolution_image,
      :python_resolution_image,
      :pip_index_url,
      :pip_extra_index_url,
      :search_ignore_hidden_dirs
    )
  end
end
