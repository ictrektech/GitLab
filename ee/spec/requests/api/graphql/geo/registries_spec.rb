# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gets registries', feature_category: :geo_replication do
  it_behaves_like 'gets registries for', {
    field_name: 'abuseReportUploadRegistries',
    registry_class_name: 'AbuseReportUploadRegistry',
    registry_factory: :geo_abuse_report_upload_registry,
    registry_foreign_key_field_name: 'abuseReportUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'achievementUploadRegistries',
    registry_class_name: 'AchievementUploadRegistry',
    registry_factory: :geo_achievement_upload_registry,
    registry_foreign_key_field_name: 'achievementUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'aiVectorizableFileUploadRegistries',
    registry_class_name: 'AiVectorizableFileUploadRegistry',
    registry_factory: :geo_ai_vectorizable_file_upload_registry,
    registry_foreign_key_field_name: 'aiVectorizableFileUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'alertManagementMetricImageUploadRegistries',
    registry_class_name: 'AlertManagementMetricImageUploadRegistry',
    registry_factory: :geo_alert_management_metric_image_upload_registry,
    registry_foreign_key_field_name: 'alertManagementMetricImageUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'appearanceUploadRegistries',
    registry_class_name: 'AppearanceUploadRegistry',
    registry_factory: :geo_appearance_upload_registry,
    registry_foreign_key_field_name: 'appearanceUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'bulkImportExportUploadUploadRegistries',
    registry_class_name: 'BulkImportExportUploadUploadRegistry',
    registry_factory: :geo_bulk_import_export_upload_upload_registry,
    registry_foreign_key_field_name: 'bulkImportExportUploadUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'ciSecureFileRegistries',
    registry_class_name: 'CiSecureFileRegistry',
    registry_factory: :geo_ci_secure_file_registry,
    registry_foreign_key_field_name: 'ciSecureFileId'
  }

  context 'for container repository registries' do
    before do
      stub_container_registry_config(enabled: true)
      stub_geo_setting(registry_replication: { enabled: true })
    end

    it_behaves_like 'gets registries for', {
      field_name: 'containerRepositoryRegistries',
      registry_class_name: 'ContainerRepositoryRegistry',
      registry_factory: :geo_container_repository_registry,
      registry_foreign_key_field_name: 'containerRepositoryId'
    }
  end

  it_behaves_like 'gets registries for', {
    field_name: 'dependencyListExportPartUploadRegistries',
    registry_class_name: 'DependencyListExportPartUploadRegistry',
    registry_factory: :geo_dependency_list_export_part_upload_registry,
    registry_foreign_key_field_name: 'dependencyListExportPartUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'dependencyListExportUploadRegistries',
    registry_class_name: 'DependencyListExportUploadRegistry',
    registry_factory: :geo_dependency_list_export_upload_registry,
    registry_foreign_key_field_name: 'dependencyListExportUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'dependencyProxyBlobRegistries',
    registry_class_name: 'DependencyProxyBlobRegistry',
    registry_factory: :geo_dependency_proxy_blob_registry,
    registry_foreign_key_field_name: 'dependencyProxyBlobId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'dependencyProxyManifestRegistries',
    registry_class_name: 'DependencyProxyManifestRegistry',
    registry_factory: :geo_dependency_proxy_manifest_registry,
    registry_foreign_key_field_name: 'dependencyProxyManifestId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'designManagementActionUploadRegistries',
    registry_class_name: 'DesignManagementActionUploadRegistry',
    registry_factory: :geo_design_management_action_upload_registry,
    registry_foreign_key_field_name: 'designManagementActionUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'designManagementRepositoryRegistries',
    registry_class_name: 'DesignManagementRepositoryRegistry',
    registry_factory: :geo_design_management_repository_registry,
    registry_foreign_key_field_name: 'designManagementRepositoryId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'groupUploadRegistries',
    registry_class_name: 'GroupUploadRegistry',
    registry_factory: :geo_group_upload_registry,
    registry_foreign_key_field_name: 'groupUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'groupWikiRepositoryRegistries',
    registry_class_name: 'GroupWikiRepositoryRegistry',
    registry_factory: :geo_group_wiki_repository_registry,
    registry_foreign_key_field_name: 'groupWikiRepositoryId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'importExportUploadUploadRegistries',
    registry_class_name: 'ImportExportUploadUploadRegistry',
    registry_factory: :geo_import_export_upload_upload_registry,
    registry_foreign_key_field_name: 'importExportUploadUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'issuableMetricImageUploadRegistries',
    registry_class_name: 'IssuableMetricImageUploadRegistry',
    registry_factory: :geo_issuable_metric_image_upload_registry,
    registry_foreign_key_field_name: 'issuableMetricImageUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'jobArtifactRegistries',
    registry_class_name: 'JobArtifactRegistry',
    registry_factory: :geo_job_artifact_registry,
    registry_foreign_key_field_name: 'artifactId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'lfsObjectRegistries',
    registry_class_name: 'LfsObjectRegistry',
    registry_factory: :geo_lfs_object_registry,
    registry_foreign_key_field_name: 'lfsObjectId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'mergeRequestDiffRegistries',
    registry_class_name: 'MergeRequestDiffRegistry',
    registry_factory: :geo_merge_request_diff_registry,
    registry_foreign_key_field_name: 'mergeRequestDiffId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'organizationDetailUploadRegistries',
    registry_class_name: 'OrganizationDetailUploadRegistry',
    registry_factory: :geo_organization_detail_upload_registry,
    registry_foreign_key_field_name: 'organizationDetailUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'packageFileRegistries',
    registry_class_name: 'PackageFileRegistry',
    registry_factory: :geo_package_file_registry,
    registry_foreign_key_field_name: 'packageFileId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'packagesDebianProjectComponentFileRegistries',
    registry_class_name: 'PackagesDebianProjectComponentFileRegistry',
    registry_factory: :geo_packages_debian_project_component_file_registry,
    registry_foreign_key_field_name: 'packagesDebianProjectComponentFileId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'packagesHelmMetadataCacheRegistries',
    registry_class_name: 'PackagesHelmMetadataCacheRegistry',
    registry_factory: :geo_packages_helm_metadata_cache_registry,
    registry_foreign_key_field_name: 'packagesHelmMetadataCacheId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'packagesNugetSymbolRegistries',
    registry_class_name: 'PackagesNugetSymbolRegistry',
    registry_factory: :geo_packages_nuget_symbol_registry,
    registry_foreign_key_field_name: 'packagesNugetSymbolId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'pagesDeploymentRegistries',
    registry_class_name: 'PagesDeploymentRegistry',
    registry_factory: :geo_pages_deployment_registry,
    registry_foreign_key_field_name: 'pagesDeploymentId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'personalSnippetUploadRegistries',
    registry_class_name: 'PersonalSnippetUploadRegistry',
    registry_factory: :geo_personal_snippet_upload_registry,
    registry_foreign_key_field_name: 'personalSnippetUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'pipelineArtifactRegistries',
    registry_class_name: 'PipelineArtifactRegistry',
    registry_factory: :geo_pipeline_artifact_registry,
    registry_foreign_key_field_name: 'pipelineArtifactId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'projectImportExportRelationExportUploadUploadRegistries',
    registry_class_name: 'ProjectImportExportRelationExportUploadUploadRegistry',
    registry_factory: :geo_project_import_export_relation_export_upload_upload_registry,
    registry_foreign_key_field_name: 'projectImportExportRelationExportUploadUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'projectRepositoryRegistries',
    registry_class_name: 'ProjectRepositoryRegistry',
    registry_factory: :geo_project_repository_registry,
    registry_foreign_key_field_name: 'projectId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'projectTopicUploadRegistries',
    registry_class_name: 'ProjectTopicUploadRegistry',
    registry_factory: :geo_project_topic_upload_registry,
    registry_foreign_key_field_name: 'projectTopicUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'projectUploadRegistries',
    registry_class_name: 'ProjectUploadRegistry',
    registry_factory: :geo_project_upload_registry,
    registry_foreign_key_field_name: 'projectUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'projectWikiRepositoryRegistries',
    registry_class_name: 'ProjectWikiRepositoryRegistry',
    registry_factory: :geo_project_wiki_repository_registry,
    registry_foreign_key_field_name: 'projectWikiRepositoryId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'snippetRepositoryRegistries',
    registry_class_name: 'SnippetRepositoryRegistry',
    registry_factory: :geo_snippet_repository_registry,
    registry_foreign_key_field_name: 'snippetRepositoryId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'terraformStateVersionRegistries',
    registry_class_name: 'TerraformStateVersionRegistry',
    registry_factory: :geo_terraform_state_version_registry,
    registry_foreign_key_field_name: 'terraformStateVersionId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'uploadRegistries',
    registry_class_name: 'UploadRegistry',
    registry_factory: :geo_upload_registry,
    registry_foreign_key_field_name: 'fileId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'userPermissionExportUploadUploadRegistries',
    registry_class_name: 'UserPermissionExportUploadUploadRegistry',
    registry_factory: :geo_user_permission_export_upload_upload_registry,
    registry_foreign_key_field_name: 'userPermissionExportUploadUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'userUploadRegistries',
    registry_class_name: 'UserUploadRegistry',
    registry_factory: :geo_user_upload_registry,
    registry_foreign_key_field_name: 'userUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'vulnerabilityArchiveExportUploadRegistries',
    registry_class_name: 'VulnerabilityArchiveExportUploadRegistry',
    registry_factory: :geo_vulnerability_archive_export_upload_registry,
    registry_foreign_key_field_name: 'vulnerabilityArchiveExportUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'vulnerabilityExportPartUploadRegistries',
    registry_class_name: 'VulnerabilityExportPartUploadRegistry',
    registry_factory: :geo_vulnerability_export_part_upload_registry,
    registry_foreign_key_field_name: 'vulnerabilityExportPartUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'vulnerabilityExportUploadRegistries',
    registry_class_name: 'VulnerabilityExportUploadRegistry',
    registry_factory: :geo_vulnerability_export_upload_registry,
    registry_foreign_key_field_name: 'vulnerabilityExportUploadId'
  }

  it_behaves_like 'gets registries for', {
    field_name: 'vulnerabilityRemediationUploadRegistries',
    registry_class_name: 'VulnerabilityRemediationUploadRegistry',
    registry_factory: :geo_vulnerability_remediation_upload_registry,
    registry_foreign_key_field_name: 'vulnerabilityRemediationUploadId'
  }

  describe 'granular token authorization' do
    include GraphqlHelpers
    include EE::GeoHelpers

    let_it_be(:user) { create(:user, :admin) }
    let_it_be(:secondary) { create(:geo_node) }
    let_it_be(:registry) { create(:geo_abuse_report_upload_registry) }

    let(:boundary_object) { :instance }
    let(:query) { '{ geoNode { abuseReportUploadRegistries { nodes { id } } } }' }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    before do
      stub_current_geo_node(secondary)
      stub_current_node_name(secondary.name)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_geo_node, :read_geo_registry]

    context 'with granular token permissions' do
      let(:pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(boundary_object), permissions: permissions)
      end

      context 'when the token has the read_geo_node and read_geo_registry permissions' do
        let(:permissions) { [:read_geo_node, :read_geo_registry] }

        it 'returns registries' do
          request

          expect(graphql_data_at(:geo_node, :abuse_report_upload_registries, :nodes))
            .to contain_exactly('id' => registry.to_global_id.to_s)
        end
      end

      context 'when the token only has the read_geo_node permission' do
        let(:permissions) { [:read_geo_node] }

        it 'does not return registries' do
          request

          expect(graphql_data_at(:geo_node)).to be_present
          expect(graphql_data_at(:geo_node, :abuse_report_upload_registries, :nodes)).to be_empty
        end
      end
    end
  end
end
