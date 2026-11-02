# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::RedactionService, feature_category: :permissions do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:private_group) { create(:group, :private) }
  let_it_be(:private_group_with_access) { create(:group, :private) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:private_project) { create(:project, :private, group: private_group) }
  let_it_be(:private_project_with_access) { create(:project, :private, group: private_group_with_access) }

  before_all do
    private_group_with_access.add_developer(user)
  end

  before do
    stub_licensed_features(epics: true, security_dashboard: true)
  end

  describe '.supported_types' do
    it 'includes EE resource types' do
      expect(described_class.supported_types).to include(
        'epic', 'vulnerability', 'ci_pipeline', 'ci_stage', 'ci_build', 'ci_runner',
        'label', 'note', 'security_scan', 'security_finding',
        'vulnerability_scanner', 'vulnerability_occurrence', 'vulnerability_identifier',
        'deployment', 'environment', 'package', 'package_file', 'dependency', 'container_repository',
        'sbom_occurrence', 'todo', 'duo_workflow', 'member_role', 'ai_catalog_item'
      )
    end

    it 'includes CE resource types' do
      expect(described_class.supported_types).to include(
        'issue', 'merge_request', 'project', 'milestone', 'snippet', 'user', 'group'
      )
    end
  end

  describe '#execute' do
    subject(:result) { service.execute }

    let(:current_user) { user }
    let(:service) { described_class.new(user: current_user, resources_by_type: resources_by_type, source: 'test') }

    context 'with epics' do
      let_it_be(:public_epic) { create(:epic, group: group) }
      let_it_be(:private_epic) { create(:epic, group: private_group) }
      let_it_be(:accessible_epic) { create(:epic, group: private_group_with_access) }
      let_it_be(:confidential_epic) { create(:epic, :confidential, group: private_group_with_access) }

      context 'when user can access public epic' do
        let(:resources_by_type) { { 'epic' => { 'ids' => [public_epic.id], 'ability' => 'read_epic' } } }

        it 'allows access' do
          expect(result).to eq({ 'epic' => { public_epic.id => true } })
        end
      end

      context 'when user cannot access private epic' do
        let(:resources_by_type) { { 'epic' => { 'ids' => [private_epic.id], 'ability' => 'read_epic' } } }

        it 'denies access' do
          expect(result).to eq({ 'epic' => { private_epic.id => false } })
        end
      end

      context 'when user has group access' do
        let(:resources_by_type) { { 'epic' => { 'ids' => [accessible_epic.id], 'ability' => 'read_epic' } } }

        it 'allows access' do
          expect(result).to eq({ 'epic' => { accessible_epic.id => true } })
        end
      end

      context 'when user has group access to confidential epic' do
        let(:resources_by_type) { { 'epic' => { 'ids' => [confidential_epic.id], 'ability' => 'read_epic' } } }

        it 'allows access for group member' do
          expect(result).to eq({ 'epic' => { confidential_epic.id => true } })
        end
      end

      context 'when checking multiple epics at once' do
        let(:resources_by_type) do
          { 'epic' => { 'ids' => [public_epic.id, private_epic.id, accessible_epic.id],
                        'ability' => 'read_epic' } }
        end

        it 'returns correct authorization for each epic' do
          expect(result).to eq({
            'epic' => {
              public_epic.id => true,
              private_epic.id => false,
              accessible_epic.id => true
            }
          })
        end
      end

      context 'with non-existent epic' do
        let(:resources_by_type) { { 'epic' => { 'ids' => [non_existing_record_id], 'ability' => 'read_epic' } } }

        it 'denies access' do
          expect(result).to eq({ 'epic' => { non_existing_record_id => false } })
        end
      end
    end

    context 'with vulnerabilities' do
      let_it_be(:accessible_vulnerability) { create(:vulnerability, project: private_project_with_access) }
      let_it_be(:inaccessible_vulnerability) { create(:vulnerability, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'vulnerability' => { 'ids' => [accessible_vulnerability.id], 'ability' => 'read_vulnerability' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'vulnerability' => { accessible_vulnerability.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'vulnerability' => { 'ids' => [inaccessible_vulnerability.id], 'ability' => 'read_vulnerability' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'vulnerability' => { inaccessible_vulnerability.id => false } })
        end
      end

      context 'when checking multiple vulnerabilities at once' do
        let(:resources_by_type) do
          { 'vulnerability' => { 'ids' => [accessible_vulnerability.id, inaccessible_vulnerability.id],
                                 'ability' => 'read_vulnerability' } }
        end

        it 'returns correct authorization for each vulnerability' do
          expect(result).to eq({
            'vulnerability' => {
              accessible_vulnerability.id => true,
              inaccessible_vulnerability.id => false
            }
          })
        end
      end

      context 'with non-existent vulnerability' do
        let(:resources_by_type) do
          { 'vulnerability' => { 'ids' => [non_existing_record_id], 'ability' => 'read_vulnerability' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'vulnerability' => { non_existing_record_id => false } })
        end
      end
    end

    context 'with ci_pipelines' do
      let_it_be(:accessible_pipeline) { create(:ci_pipeline, project: private_project_with_access) }
      let_it_be(:inaccessible_pipeline) { create(:ci_pipeline, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'ci_pipeline' => { 'ids' => [accessible_pipeline.id], 'ability' => 'read_pipeline' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'ci_pipeline' => { accessible_pipeline.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'ci_pipeline' => { 'ids' => [inaccessible_pipeline.id], 'ability' => 'read_pipeline' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'ci_pipeline' => { inaccessible_pipeline.id => false } })
        end
      end
    end

    context 'with packages' do
      let_it_be(:accessible_package) { create(:generic_package, project: private_project_with_access) }
      let_it_be(:inaccessible_package) { create(:generic_package, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'package' => { 'ids' => [accessible_package.id], 'ability' => 'read_package' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'package' => { accessible_package.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'package' => { 'ids' => [inaccessible_package.id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'package' => { inaccessible_package.id => false } })
        end
      end

      context 'with non-existent package' do
        let(:resources_by_type) do
          { 'package' => { 'ids' => [non_existing_record_id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'package' => { non_existing_record_id => false } })
        end
      end
    end

    context 'with package_files' do
      let_it_be(:accessible_package) { create(:generic_package, project: private_project_with_access) }
      let_it_be(:inaccessible_package) { create(:generic_package, project: private_project) }
      let_it_be(:accessible_package_file) { create(:package_file, package: accessible_package) }
      let_it_be(:inaccessible_package_file) { create(:package_file, package: inaccessible_package) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'package_file' => { 'ids' => [accessible_package_file.id], 'ability' => 'read_package' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'package_file' => { accessible_package_file.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'package_file' => { 'ids' => [inaccessible_package_file.id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'package_file' => { inaccessible_package_file.id => false } })
        end
      end

      context 'with non-existent package_file' do
        let(:resources_by_type) do
          { 'package_file' => { 'ids' => [non_existing_record_id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'package_file' => { non_existing_record_id => false } })
        end
      end

      it 'preloads both the direct project and the package the policy delegates to' do
        # collect_policy_subjects preseeds the ProjectPolicyPreloader via resource.project, so the
        # direct project must be preloaded. PackageFilePolicy then delegates to the file's package,
        # which delegates to its project, so package_file -> package -> project is also preloaded.
        expect(EE::Authz::RedactionService::EE_PRELOAD_ASSOCIATIONS[:package_file]).to eq(
          [
            { project: [:namespace, :project_feature, :group, :organization] },
            { package: { project: [:namespace, :project_feature, :group, :organization] } }
          ]
        )
      end
    end

    context 'with dependencies' do
      let_it_be(:accessible_dependency) { create(:packages_dependency, project: private_project_with_access) }
      let_it_be(:inaccessible_dependency) { create(:packages_dependency, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'dependency' => { 'ids' => [accessible_dependency.id], 'ability' => 'read_package' } }
        end

        it 'allows access via the dependency project' do
          expect(result).to eq({ 'dependency' => { accessible_dependency.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'dependency' => { 'ids' => [inaccessible_dependency.id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'dependency' => { inaccessible_dependency.id => false } })
        end
      end

      context 'with non-existent dependency' do
        let(:resources_by_type) do
          { 'dependency' => { 'ids' => [non_existing_record_id], 'ability' => 'read_package' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'dependency' => { non_existing_record_id => false } })
        end
      end
    end

    context 'with container_repositories' do
      let_it_be(:accessible_repository) { create(:container_repository, project: private_project_with_access) }
      let_it_be(:inaccessible_repository) { create(:container_repository, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'container_repository' => { 'ids' => [accessible_repository.id], 'ability' => 'read_container_image' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'container_repository' => { accessible_repository.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'container_repository' => { 'ids' => [inaccessible_repository.id], 'ability' => 'read_container_image' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'container_repository' => { inaccessible_repository.id => false } })
        end
      end

      context 'with non-existent container_repository' do
        let(:resources_by_type) do
          { 'container_repository' => { 'ids' => [non_existing_record_id], 'ability' => 'read_container_image' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'container_repository' => { non_existing_record_id => false } })
        end
      end
    end

    context 'with ci_stages' do
      let_it_be(:accessible_pipeline) { create(:ci_pipeline, project: private_project_with_access) }
      let_it_be(:inaccessible_pipeline) { create(:ci_pipeline, project: private_project) }
      let_it_be(:accessible_stage) do
        create(:ci_stage, pipeline: accessible_pipeline, project: accessible_pipeline.project)
      end

      let_it_be(:inaccessible_stage) do
        create(:ci_stage, pipeline: inaccessible_pipeline, project: inaccessible_pipeline.project)
      end

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'ci_stage' => { 'ids' => [accessible_stage.id], 'ability' => 'read_build' } }
        end

        it 'allows access via pipeline delegation' do
          expect(result).to eq({ 'ci_stage' => { accessible_stage.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'ci_stage' => { 'ids' => [inaccessible_stage.id], 'ability' => 'read_build' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'ci_stage' => { inaccessible_stage.id => false } })
        end
      end
    end

    context 'with ci_builds' do
      let_it_be(:accessible_pipeline) { create(:ci_pipeline, project: private_project_with_access) }
      let_it_be(:inaccessible_pipeline) { create(:ci_pipeline, project: private_project) }
      let_it_be(:accessible_build) { create(:ci_build, pipeline: accessible_pipeline) }
      let_it_be(:accessible_bridge) { create(:ci_bridge, pipeline: accessible_pipeline) }
      let_it_be(:accessible_generic_status) { create(:generic_commit_status, pipeline: accessible_pipeline) }
      let_it_be(:inaccessible_build) { create(:ci_build, pipeline: inaccessible_pipeline) }
      let_it_be(:inaccessible_bridge) { create(:ci_bridge, pipeline: inaccessible_pipeline) }
      let_it_be(:inaccessible_generic_status) { create(:generic_commit_status, pipeline: inaccessible_pipeline) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'ci_build' => { 'ids' => [accessible_build.id, accessible_bridge.id, accessible_generic_status.id],
                            'ability' => 'read_build' } }
        end

        it 'allows builds, bridges, and generic commit statuses' do
          expect(result).to eq({
            'ci_build' => {
              accessible_build.id => true,
              accessible_bridge.id => true,
              accessible_generic_status.id => true
            }
          })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'ci_build' => { 'ids' => [inaccessible_build.id, inaccessible_bridge.id, inaccessible_generic_status.id],
                            'ability' => 'read_build' } }
        end

        it 'denies builds, bridges, and generic commit statuses' do
          expect(result).to eq({
            'ci_build' => {
              inaccessible_build.id => false,
              inaccessible_bridge.id => false,
              inaccessible_generic_status.id => false
            }
          })
        end
      end
    end

    context 'with ci_runners' do
      let_it_be(:maintained_group) { create(:group, :private) }
      let_it_be(:maintained_subgroup) { create(:group, :private, parent: maintained_group) }
      let_it_be(:maintained_project) { create(:project, :private, group: maintained_subgroup) }
      let_it_be(:other_private_group) { create(:group, :private) }

      let_it_be(:instance_runner) { create(:ci_runner, :instance) }
      let_it_be(:group_runner_at_parent) { create(:ci_runner, :group, groups: [maintained_group]) }
      let_it_be(:inaccessible_group_runner) { create(:ci_runner, :group, groups: [other_private_group]) }
      let_it_be(:project_runner) { create(:ci_runner, :project, projects: [maintained_project]) }
      let_it_be(:inaccessible_project_runner) { create(:ci_runner, :project, projects: [private_project]) }

      before_all do
        maintained_group.add_maintainer(user)
      end

      context 'when the runner is an instance runner' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [instance_runner.id], 'ability' => 'read_runner' } }
        end

        it 'allows access for any authenticated user' do
          expect(result).to eq({ 'ci_runner' => { instance_runner.id => true } })
        end
      end

      context 'when user is a maintainer of the runner group' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [group_runner_at_parent.id], 'ability' => 'read_runner' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'ci_runner' => { group_runner_at_parent.id => true } })
        end
      end

      context 'when the runner is registered at a parent group and the user owns a project that inherits it' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [group_runner_at_parent.id], 'ability' => 'read_runner' } }
        end

        it 'allows access via the subgroup project that inherits group runners' do
          expect(maintained_project.group_runners_enabled).to be true
          expect(result).to eq({ 'ci_runner' => { group_runner_at_parent.id => true } })
        end
      end

      context 'when user has no access to the runner group' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [inaccessible_group_runner.id], 'ability' => 'read_runner' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'ci_runner' => { inaccessible_group_runner.id => false } })
        end
      end

      context 'when user is a maintainer of the runner project' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [project_runner.id], 'ability' => 'read_runner' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'ci_runner' => { project_runner.id => true } })
        end
      end

      context 'when user cannot read the project runner' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [inaccessible_project_runner.id], 'ability' => 'read_runner' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'ci_runner' => { inaccessible_project_runner.id => false } })
        end
      end

      context 'when the runner id does not exist' do
        let(:resources_by_type) do
          { 'ci_runner' => { 'ids' => [non_existing_record_id], 'ability' => 'read_runner' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'ci_runner' => { non_existing_record_id => false } })
        end
      end

      context 'when the request mixes accessible and inaccessible runners' do
        let(:resources_by_type) do
          {
            'ci_runner' => {
              'ids' => [instance_runner.id, group_runner_at_parent.id, inaccessible_group_runner.id],
              'ability' => 'read_runner'
            }
          }
        end

        it 'permits the accessible ids and denies the rest' do
          expect(result).to eq({
            'ci_runner' => {
              instance_runner.id => true,
              group_runner_at_parent.id => true,
              inaccessible_group_runner.id => false
            }
          })
        end
      end
    end

    context 'with labels' do
      let_it_be(:accessible_label) { create(:label, project: private_project_with_access) }
      let_it_be(:inaccessible_label) { create(:label, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'label' => { 'ids' => [accessible_label.id], 'ability' => 'read_label' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'label' => { accessible_label.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'label' => { 'ids' => [inaccessible_label.id], 'ability' => 'read_label' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'label' => { inaccessible_label.id => false } })
        end
      end
    end

    context 'with notes' do
      let_it_be(:accessible_issue) { create(:issue, project: private_project_with_access) }
      let_it_be(:inaccessible_issue) { create(:issue, project: private_project) }
      let_it_be(:accessible_note) { create(:note, noteable: accessible_issue, project: private_project_with_access) }
      let_it_be(:inaccessible_note) { create(:note, noteable: inaccessible_issue, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'note' => { 'ids' => [accessible_note.id], 'ability' => 'read_note' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'note' => { accessible_note.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'note' => { 'ids' => [inaccessible_note.id], 'ability' => 'read_note' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'note' => { inaccessible_note.id => false } })
        end
      end
    end

    context 'with deployments' do
      let_it_be(:deploy_project_with_access) do
        create(:project, :repository, :private, group: private_group_with_access)
      end

      let_it_be(:deploy_project_without_access) do
        create(:project, :repository, :private, group: private_group)
      end

      let_it_be(:accessible_deployment) do
        create(:deployment, :success, project: deploy_project_with_access)
      end

      let_it_be(:inaccessible_deployment) do
        create(:deployment, :success, project: deploy_project_without_access)
      end

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'deployment' => { 'ids' => [accessible_deployment.id], 'ability' => 'read_deployment' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'deployment' => { accessible_deployment.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'deployment' => { 'ids' => [inaccessible_deployment.id], 'ability' => 'read_deployment' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'deployment' => { inaccessible_deployment.id => false } })
        end
      end
    end

    context 'with environments' do
      let_it_be(:accessible_environment) { create(:environment, project: private_project_with_access) }
      let_it_be(:inaccessible_environment) { create(:environment, project: private_project) }

      context 'when user has project access' do
        let(:resources_by_type) do
          { 'environment' => { 'ids' => [accessible_environment.id], 'ability' => 'read_environment' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'environment' => { accessible_environment.id => true } })
        end
      end

      context 'when user does not have project access' do
        let(:resources_by_type) do
          { 'environment' => { 'ids' => [inaccessible_environment.id], 'ability' => 'read_environment' } }
        end

        it 'denies access' do
          expect(result).to eq({ 'environment' => { inaccessible_environment.id => false } })
        end
      end
    end

    context 'with deployments and environments via shared group' do
      let_it_be(:shared_group) { create(:group, :private) }
      let_it_be(:shared_project) { create(:project, :repository, :private, group: shared_group) }
      let_it_be(:shared_environment) { create(:environment, project: shared_project) }
      let_it_be(:shared_deployment) { create(:deployment, :success, project: shared_project) }

      before_all do
        create(:project_group_link, project: shared_project, group: private_group_with_access)
      end

      context 'when user has access via shared group link' do
        let(:resources_by_type) do
          {
            'deployment' => { 'ids' => [shared_deployment.id], 'ability' => 'read_deployment' },
            'environment' => { 'ids' => [shared_environment.id], 'ability' => 'read_environment' }
          }
        end

        it 'allows access through group link' do
          expect(result).to eq({
            'deployment' => { shared_deployment.id => true },
            'environment' => { shared_environment.id => true }
          })
        end
      end
    end

    context 'with deployments and environments via group-to-group link' do
      let_it_be(:target_group) { create(:group, :private) }
      let_it_be(:target_project) { create(:project, :repository, :private, group: target_group) }
      let_it_be(:target_environment) { create(:environment, project: target_project) }
      let_it_be(:target_deployment) { create(:deployment, :success, project: target_project) }

      before_all do
        create(:group_group_link, shared_group: target_group, shared_with_group: private_group_with_access)
      end

      before do
        user.refresh_authorized_projects
      end

      context 'when user has access via group-to-group share' do
        let(:resources_by_type) do
          {
            'deployment' => { 'ids' => [target_deployment.id], 'ability' => 'read_deployment' },
            'environment' => { 'ids' => [target_environment.id], 'ability' => 'read_environment' }
          }
        end

        it 'allows access through group-to-group link' do
          expect(result).to eq({
            'deployment' => { target_deployment.id => true },
            'environment' => { target_environment.id => true }
          })
        end
      end
    end

    context 'when user has no group-to-group link access' do
      let_it_be(:isolated_group) { create(:group, :private) }
      let_it_be(:isolated_project) { create(:project, :repository, :private, group: isolated_group) }
      let_it_be(:isolated_environment) { create(:environment, project: isolated_project) }
      let_it_be(:isolated_deployment) { create(:deployment, :success, project: isolated_project) }

      let(:resources_by_type) do
        {
          'deployment' => { 'ids' => [isolated_deployment.id], 'ability' => 'read_deployment' },
          'environment' => { 'ids' => [isolated_environment.id], 'ability' => 'read_environment' }
        }
      end

      it 'denies access without group-to-group link' do
        expect(result).to eq({
          'deployment' => { isolated_deployment.id => false },
          'environment' => { isolated_environment.id => false }
        })
      end
    end

    context 'with deployments and environments mixed authorization' do
      let_it_be(:deploy_project) { create(:project, :repository, :private, group: private_group_with_access) }
      let_it_be(:no_access_project) { create(:project, :repository, :private, group: private_group) }
      let_it_be(:accessible_deploy) { create(:deployment, :success, project: deploy_project) }
      let_it_be(:inaccessible_deploy) { create(:deployment, :success, project: no_access_project) }
      let_it_be(:accessible_env) { create(:environment, project: private_project_with_access) }
      let_it_be(:inaccessible_env) { create(:environment, project: private_project) }

      let(:resources_by_type) do
        {
          'deployment' => {
            'ids' => [accessible_deploy.id, inaccessible_deploy.id, non_existing_record_id],
            'ability' => 'read_deployment'
          },
          'environment' => {
            'ids' => [accessible_env.id, inaccessible_env.id, non_existing_record_id],
            'ability' => 'read_environment'
          }
        }
      end

      it 'returns correct authorization for each resource' do
        expect(result).to eq({
          'deployment' => {
            accessible_deploy.id => true,
            inaccessible_deploy.id => false,
            non_existing_record_id => false
          },
          'environment' => {
            accessible_env.id => true,
            inaccessible_env.id => false,
            non_existing_record_id => false
          }
        })
      end
    end

    context 'with sbom occurrences' do
      let_it_be(:reporter) { create(:user, reporter_of: private_project) }
      let_it_be(:guest) { create(:user, guest_of: private_project) }
      let_it_be(:occurrence) { create(:sbom_occurrence, project: private_project) }

      let(:resources_by_type) do
        { 'sbom_occurrence' => { 'ids' => [occurrence.id, non_existing_record_id], 'ability' => 'read_dependency' } }
      end

      before do
        stub_licensed_features(dependency_scanning: true)
      end

      context 'when user is a reporter of the project' do
        let(:current_user) { reporter }

        it 'allows access' do
          expect(result).to eq({ 'sbom_occurrence' => { occurrence.id => true, non_existing_record_id => false } })
        end
      end

      context 'when user is a guest of the project' do
        let(:current_user) { guest }

        it 'denies access' do
          expect(result).to eq({ 'sbom_occurrence' => { occurrence.id => false, non_existing_record_id => false } })
        end
      end

      context 'when user is not a member of the project' do
        it 'denies access' do
          expect(result).to eq({ 'sbom_occurrence' => { occurrence.id => false, non_existing_record_id => false } })
        end
      end

      context 'when dependency scanning is not licensed' do
        let(:current_user) { reporter }

        before do
          stub_licensed_features(dependency_scanning: false)
        end

        it 'denies access' do
          expect(result).to eq({ 'sbom_occurrence' => { occurrence.id => false, non_existing_record_id => false } })
        end
      end

      context 'when the reporter is banned from the top-level group' do
        let(:current_user) { reporter }

        before do
          stub_licensed_features(dependency_scanning: true, unique_project_download_limit: true)
          create(:namespace_ban, namespace: private_group, user: reporter)
          reporter.namespace_bans.reset
        end

        it 'denies access' do
          expect(result).to eq({ 'sbom_occurrence' => { occurrence.id => false, non_existing_record_id => false } })
        end
      end
    end

    context 'with todos' do
      let_it_be(:other_user) { create(:user) }
      let_it_be(:issue) { create(:issue, project: project) }
      let_it_be(:confidential_issue) { create(:issue, :confidential, project: project) }
      let_it_be(:private_issue) { create(:issue, project: private_project_with_access) }
      let_it_be(:internal_note) { create(:note, :confidential, noteable: issue, project: project) }

      let_it_be(:own_todo) { create(:todo, user: user, project: project, target: issue) }
      let_it_be(:own_private_todo) do
        create(:todo, user: user, project: private_project_with_access, target: private_issue)
      end

      let_it_be(:other_user_todo) { create(:todo, user: other_user, project: project, target: issue) }
      let_it_be(:confidential_target_todo) do
        create(:todo, user: user, project: project, target: confidential_issue)
      end

      let_it_be(:internal_note_todo) do
        create(:todo, :mentioned, user: user, project: project, target: issue, note: internal_note)
      end

      let_it_be(:group_todo) do
        epic = create(:epic, group: private_group_with_access)
        create(:todo, user: user, group: private_group_with_access, target: epic)
      end

      let_it_be(:inaccessible_group_todo) do
        create(:todo, user: user, group: private_group, target: create(:epic, group: private_group))
      end

      let_it_be(:deleted_target_todo) do
        create(:todo, user: user, project: project, target: issue).tap do |todo|
          todo.update_column(:target_id, non_existing_record_id)
        end
      end

      let(:resources_by_type) do
        {
          'todo' => {
            'ids' => [own_todo.id, own_private_todo.id, other_user_todo.id, confidential_target_todo.id,
              internal_note_todo.id, group_todo.id, inaccessible_group_todo.id, deleted_target_todo.id,
              non_existing_record_id],
            'ability' => 'read_todo'
          }
        }
      end

      it 'allows only own todos with a readable target' do
        expect(result).to eq({
          'todo' => {
            own_todo.id => true,
            own_private_todo.id => true,
            other_user_todo.id => false,
            confidential_target_todo.id => false,
            internal_note_todo.id => false,
            group_todo.id => true,
            inaccessible_group_todo.id => false,
            deleted_target_todo.id => false,
            non_existing_record_id => false
          }
        })
      end

      context 'when the owner can read the confidential target and the internal note' do
        before_all do
          project.add_reporter(user)
        end

        it 'allows the own todos' do
          expect(result['todo']).to include(confidential_target_todo.id => true, internal_note_todo.id => true)
        end
      end
    end

    context 'with an own todo behind an expired group SAML session' do
      let_it_be(:saml_group) { create(:group, :private) }
      let_it_be(:saml_provider) { create(:saml_provider, group: saml_group, enabled: true, enforced_sso: true) }
      let_it_be(:saml_project) { create(:project, :private, group: saml_group, developers: user) }
      let_it_be(:saml_todo) do
        create(:todo, user: user, project: saml_project, target: create(:issue, project: saml_project))
      end

      let(:resources_by_type) { { 'todo' => { 'ids' => [saml_todo.id], 'ability' => 'read_todo' } } }
      let(:web_session) { { 'warden.user.user.key' => [[user.id], user.authenticatable_salt] } }

      before do
        stub_licensed_features(group_saml: true)
      end

      it 'allows access as the product policy does, although the product masks the target fields' do
        Gitlab::Session.with_session(web_session) do
          expect(saml_todo.target.readable_by?(user)).to be(false)
          expect(result).to eq({ 'todo' => { saml_todo.id => true } })
        end
      end
    end

    context 'with a todo on a commit' do
      let_it_be(:repository_project) { create(:project, :repository, :private, group: private_group_with_access) }
      let_it_be(:commit_todo) { create(:on_commit_todo, user: user, project: repository_project, author: user) }
      let_it_be(:other_user_commit_todo) do
        create(:on_commit_todo, user: create(:user), project: repository_project, author: user)
      end

      let(:resources_by_type) do
        { 'todo' => { 'ids' => [commit_todo.id, other_user_commit_todo.id], 'ability' => 'read_todo' } }
      end

      it 'allows only the own todo' do
        expect(result).to eq({ 'todo' => { commit_todo.id => true, other_user_commit_todo.id => false } })
      end
    end

    context 'with duo workflows' do
      let_it_be(:other_user) { create(:user, developer_of: private_project_with_access) }
      let_it_be(:own_workflow) do
        create(:duo_workflows_workflow, project: private_project_with_access, user: user, environment: :ide)
      end

      let_it_be(:other_user_workflow) do
        create(:duo_workflows_workflow, project: private_project_with_access, user: other_user, environment: :ide)
      end

      let_it_be(:pipeline_workflow) do
        create(:duo_workflows_workflow, project: private_project_with_access, user: other_user, environment: :ambient)
      end

      let_it_be(:private_messaging_workflow) do
        create(:duo_workflows_workflow, project: private_project_with_access, user: other_user,
          environment: :ambient, messaging_callback_context: { 'adapter' => 'slack' })
      end

      let_it_be(:other_user_chat) do
        create(:duo_workflows_workflow, :agentic_chat, project: private_project_with_access, user: other_user)
      end

      let_it_be(:namespace_workflow) do
        create(:duo_workflows_workflow, namespace: private_group_with_access, user: user, environment: :ide)
      end

      let_it_be(:inaccessible_workflow) do
        create(:duo_workflows_workflow, project: private_project, user: create(:user, developer_of: private_project),
          environment: :ambient)
      end

      let_it_be(:other_user_namespace_workflow) do
        create(:duo_workflows_workflow, namespace: private_group_with_access, user: other_user, environment: :ide)
      end

      let_it_be(:inaccessible_namespace_workflow) do
        create(:duo_workflows_workflow, namespace: private_group, user: create(:user), environment: :ide)
      end

      let(:resources_by_type) do
        {
          'duo_workflow' => {
            'ids' => [own_workflow.id, other_user_workflow.id, pipeline_workflow.id, private_messaging_workflow.id,
              other_user_chat.id, namespace_workflow.id, inaccessible_workflow.id, other_user_namespace_workflow.id,
              inaccessible_namespace_workflow.id, non_existing_record_id],
            'ability' => 'read_duo_workflow'
          }
        }
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
        allow(user).to receive(:allowed_to_use?).and_return(true)
      end

      it 'allows own workflows and pipeline-started workflows in readable projects' do
        expect(result).to eq({
          'duo_workflow' => {
            own_workflow.id => true,
            other_user_workflow.id => false,
            pipeline_workflow.id => true,
            private_messaging_workflow.id => false,
            other_user_chat.id => false,
            namespace_workflow.id => true,
            inaccessible_workflow.id => false,
            other_user_namespace_workflow.id => false,
            inaccessible_namespace_workflow.id => false,
            non_existing_record_id => false
          }
        })
      end

      context 'when the user cannot use Duo workflows' do
        before do
          allow(user).to receive(:allowed_to_use?).and_return(false)
        end

        it 'denies access' do
          expect(result['duo_workflow'].values).to all(be(false))
        end
      end

      context 'when the user is a compliance reviewer of the group' do
        let_it_be(:reviewer) { create(:user, owner_of: private_group_with_access) }

        let(:current_user) { reviewer }

        before do
          stub_licensed_features(project_level_compliance_dashboard: true, group_level_compliance_dashboard: true)
        end

        it 'allows the non-chat workflows of other users, but not their chats' do
          expect(result['duo_workflow']).to include(
            other_user_workflow.id => true,
            pipeline_workflow.id => true,
            other_user_chat.id => false,
            private_messaging_workflow.id => false,
            inaccessible_workflow.id => false
          )
        end
      end
    end

    context 'with member roles' do
      let_it_be(:accessible_role) { create(:member_role, namespace: private_group_with_access) }
      let_it_be(:inaccessible_role) { create(:member_role, namespace: private_group) }
      let_it_be(:instance_role) { create(:member_role, :instance) }
      let_it_be(:admin_role) { create(:member_role, :read_admin_users) }
      let_it_be(:root_guest) { create(:user, guest_of: private_group_with_access) }
      let_it_be(:subgroup_member) do
        create(:user).tap { |member| create(:group, :private, parent: private_group_with_access).add_developer(member) }
      end

      let(:resources_by_type) do
        {
          'member_role' => {
            'ids' => [accessible_role.id, inaccessible_role.id, instance_role.id, admin_role.id,
              non_existing_record_id],
            'ability' => 'read_member_role'
          }
        }
      end

      context 'when custom roles are licensed' do
        before do
          stub_licensed_features(custom_roles: true)
        end

        it 'allows roles of readable groups and instance roles, but not admin roles' do
          expect(result).to eq({
            'member_role' => {
              accessible_role.id => true,
              inaccessible_role.id => false,
              instance_role.id => true,
              admin_role.id => false,
              non_existing_record_id => false
            }
          })
        end
      end

      context 'when custom roles are not licensed' do
        before do
          stub_licensed_features(custom_roles: false)
        end

        it 'denies access' do
          expect(result['member_role'].values).to all(be(false))
        end
      end

      context 'when the user is a guest of the top-level group' do
        let(:current_user) { root_guest }

        before do
          stub_licensed_features(custom_roles: true)
        end

        it 'allows the group role' do
          expect(result['member_role']).to include(accessible_role.id => true, inaccessible_role.id => false)
        end
      end

      context 'when the user is a member of a subgroup only' do
        let(:current_user) { subgroup_member }

        before do
          stub_licensed_features(custom_roles: true)
        end

        it 'denies the group role' do
          expect(result['member_role']).to include(accessible_role.id => false, inaccessible_role.id => false)
        end
      end
    end

    context 'with ai catalog items' do
      let_it_be(:public_item) { create(:ai_catalog_item, :public, project: private_project) }
      let_it_be(:restricted_item) { create(:ai_catalog_item, :restricted, project: private_project_with_access) }
      let_it_be(:inaccessible_restricted_item) { create(:ai_catalog_item, :restricted, project: private_project) }
      let_it_be(:private_item) { create(:ai_catalog_item, :private, project: private_project_with_access) }
      let_it_be(:inaccessible_private_item) { create(:ai_catalog_item, :private, project: private_project) }
      let_it_be(:deleted_public_item) { create(:ai_catalog_item, :public, :soft_deleted, project: private_project) }

      let(:resources_by_type) do
        {
          'ai_catalog_item' => {
            'ids' => [public_item.id, restricted_item.id, inaccessible_restricted_item.id, private_item.id,
              inaccessible_private_item.id, deleted_public_item.id, non_existing_record_id],
            'ability' => 'read_ai_catalog_item'
          }
        }
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
      end

      it 'allows public items and items in the hierarchy of the user' do
        expect(result).to eq({
          'ai_catalog_item' => {
            public_item.id => true,
            restricted_item.id => true,
            inaccessible_restricted_item.id => false,
            private_item.id => true,
            inaccessible_private_item.id => false,
            deleted_public_item.id => false,
            non_existing_record_id => false
          }
        })
      end

      context 'when the AI catalog is not available in the project' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(false)
        end

        it 'allows only public items' do
          expect(result['ai_catalog_item'].select { |_id, allowed| allowed }.keys).to eq([public_item.id])
        end
      end

      context 'when the user has no AI catalog access' do
        before do
          allow(user).to receive(:allowed_to_use_through_namespace?).and_call_original
          allow(user).to receive(:allowed_to_use_through_namespace?).with(:ai_catalog).and_return(false)
        end

        it 'denies access to every item' do
          expect(result['ai_catalog_item'].values).to all(be(false))
        end
      end

      context 'with a third-party flow' do
        let_it_be(:third_party_flow) do
          create(:ai_catalog_third_party_flow, :private, project: private_project_with_access)
        end

        let(:resources_by_type) do
          { 'ai_catalog_item' => { 'ids' => [third_party_flow.id], 'ability' => 'read_ai_catalog_item' } }
        end

        it 'allows access' do
          expect(result).to eq({ 'ai_catalog_item' => { third_party_flow.id => true } })
        end

        context 'when third-party flows are disabled' do
          before do
            stub_feature_flags(ai_catalog_third_party_flows: false)
          end

          it 'denies access' do
            expect(result).to eq({ 'ai_catalog_item' => { third_party_flow.id => false } })
          end
        end
      end
    end

    context 'with mixed CE and EE resource types' do
      let_it_be(:public_issue) { create(:issue, project: project) }
      let_it_be(:public_epic) { create(:epic, group: group) }
      let_it_be(:accessible_vulnerability) { create(:vulnerability, project: private_project_with_access) }
      let_it_be(:private_mr) { create(:merge_request, source_project: private_project) }

      let(:resources_by_type) do
        {
          'issue' => { 'ids' => [public_issue.id], 'ability' => 'read_issue' },
          'epic' => { 'ids' => [public_epic.id], 'ability' => 'read_epic' },
          'vulnerability' => { 'ids' => [accessible_vulnerability.id], 'ability' => 'read_vulnerability' },
          'merge_request' => { 'ids' => [private_mr.id], 'ability' => 'read_merge_request' }
        }
      end

      it 'handles both CE and EE resource types correctly' do
        expect(result).to eq({
          'issue' => { public_issue.id => true },
          'epic' => { public_epic.id => true },
          'vulnerability' => { accessible_vulnerability.id => true },
          'merge_request' => { private_mr.id => false }
        })
      end
    end

    context 'with empty arrays for EE types' do
      let(:resources_by_type) do
        {
          'epic' => { 'ids' => [], 'ability' => 'read_epic' },
          'vulnerability' => { 'ids' => [], 'ability' => 'read_vulnerability' }
        }
      end

      it 'returns empty hashes for those types' do
        expect(result).to eq({ 'epic' => {}, 'vulnerability' => {} })
      end
    end

    context 'with missing ability (fail-closed)' do
      let_it_be(:public_epic) { create(:epic, group: group) }
      let_it_be(:private_epic) { create(:epic, group: private_group) }

      context 'when no ability is provided for EE type' do
        let(:resources_by_type) do
          { 'epic' => { 'ids' => [public_epic.id, private_epic.id] } }
        end

        it 'denies access for all resources when ability is not specified' do
          expect(result).to eq({
            'epic' => {
              public_epic.id => false,
              private_epic.id => false
            }
          })
        end
      end
    end
  end

  describe 'root ancestor preloading', :request_store do
    let_it_be(:roots) { create_list(:group, 3) }
    let_it_be(:projects) { roots.map { |root| create(:project, :public, group: create(:group, parent: root)) } }
    let_it_be(:personal_project) { create(:project, :public) }

    def execute_for(projects)
      described_class.new(
        user: user,
        resources_by_type: { 'project' => { 'ids' => projects.map(&:id), 'ability' => 'read_code' } },
        source: 'test'
      ).execute
    end

    it 'does not query root ancestors once per root group' do
      control = ActiveRecord::QueryRecorder.new { execute_for(projects.first(1)) }

      expect { execute_for(projects) }.not_to exceed_query_limit(control)
    end

    it 'authorizes projects in personal namespaces' do
      expect(execute_for([personal_project])).to eq({ 'project' => { personal_project.id => true } })
    end
  end

  describe 'preloading of new resource types', :request_store do
    let_it_be(:roots) { create_list(:group, 3, :private).each { |root| root.add_developer(user) } }
    let_it_be(:projects) do
      roots.map { |root| create(:project, :private, group: create(:group, :private, parent: root)) }
    end

    let(:builders) do
      {
        'sbom_occurrence' => ->(project) { create(:sbom_occurrence, project: project) },
        'todo' => ->(project) { create(:todo, user: user, project: project, target: create(:issue, project: project)) },
        'duo_workflow' => ->(project) { create(:duo_workflows_workflow, project: project, user: user) },
        'member_role' => ->(project) { create(:member_role, namespace: project.root_ancestor) },
        'ai_catalog_item' => ->(project) { create(:ai_catalog_item, :private, project: project) }
      }
    end

    let(:abilities) do
      {
        'sbom_occurrence' => 'read_dependency',
        'todo' => 'read_todo',
        'duo_workflow' => 'read_duo_workflow',
        'member_role' => 'read_member_role',
        'ai_catalog_item' => 'read_ai_catalog_item'
      }
    end

    def execute_for(type, records)
      described_class.new(
        user: user,
        resources_by_type: { type => { 'ids' => records.map(&:id), 'ability' => abilities[type] } },
        source: 'test'
      ).execute
    end

    def control_for(type, records)
      execute_for(type, records.first(1))
      RequestStore.clear!
      ActiveRecord::QueryRecorder.new { execute_for(type, records.first(1)) }.tap { RequestStore.clear! }
    end

    before do
      stub_licensed_features(dependency_scanning: true, custom_roles: true, ai_workflows: true, ai_catalog: true)
      allow(user).to receive(:allowed_to_use?).and_return(true)
    end

    %w[sbom_occurrence todo duo_workflow member_role ai_catalog_item].each do |type|
      it "does not run queries per #{type} in the same parent" do
        records = Array.new(3) { builders[type].call(projects.first) }
        control = control_for(type, records)

        expect { execute_for(type, records) }.not_to exceed_query_limit(control)
        expect(execute_for(type, records).fetch(type).values).to all(be(true))
      end
    end

    %w[sbom_occurrence member_role].each do |type|
      it "does not run queries per parent of #{type}" do
        records = projects.map { |project| builders[type].call(project) }
        control = control_for(type, records)

        expect { execute_for(type, records) }.not_to exceed_query_limit(control)
        expect(execute_for(type, records).fetch(type).values).to all(be(true))
      end
    end

    %w[duo_workflow ai_catalog_item].each do |type|
      it "runs one Duo settings query per extra parent of #{type}" do
        records = projects.map { |project| builders[type].call(project) }
        control = control_for(type, records)

        expect { execute_for(type, records) }.not_to exceed_query_limit(control).with_threshold(records.size - 1)
        expect(execute_for(type, records).fetch(type).values).to all(be(true))
      end
    end

    it 'does not run queries per parent of a namespace-level duo_workflow' do
      records = roots.map { |root| create(:duo_workflows_workflow, namespace: root, user: user, environment: :ide) }
      control = control_for('duo_workflow', records)

      expect { execute_for('duo_workflow', records) }.not_to exceed_query_limit(control)
      expect(execute_for('duo_workflow', records).fetch('duo_workflow').values).to all(be(true))
    end
  end

  describe 'load_resources_for_type behavior' do
    context 'when EE resource type has no preload associations defined' do
      let_it_be(:public_epic) { create(:epic, group: group) }
      let(:resources_by_type) { { 'epic' => { 'ids' => [public_epic.id], 'ability' => 'read_epic' } } }
      let(:service) { described_class.new(user: user, resources_by_type: resources_by_type, source: 'test') }

      before do
        stub_const(
          "EE::Authz::RedactionService::EE_PRELOAD_ASSOCIATIONS",
          EE::Authz::RedactionService::EE_PRELOAD_ASSOCIATIONS.except(:epic)
        )
      end

      it 'does not raise an error when preloads are not defined' do
        expect { service.execute }.not_to raise_error
      end

      it 'still performs authorization correctly' do
        result = service.execute
        expect(result).to eq({ 'epic' => { public_epic.id => true } })
      end
    end

    context 'when group is handled as EE resource type' do
      let_it_be(:public_group) { create(:group, :public) }
      let(:service) { described_class.new(user: user, resources_by_type: resources_by_type, source: 'test') }

      context 'with valid group ids' do
        let(:resources_by_type) { { 'group' => { 'ids' => [public_group.id], 'ability' => 'read_group' } } }

        it 'loads and authorizes groups with EE-specific preloads' do
          result = service.execute
          expect(result).to eq({ 'group' => { public_group.id => true } })
        end
      end

      context 'with empty ids' do
        let(:resources_by_type) { { 'group' => { 'ids' => [], 'ability' => 'read_group' } } }

        it 'returns empty hash' do
          result = service.execute
          expect(result).to eq({ 'group' => {} })
        end
      end

      it 'includes group in EE_RESOURCE_CLASSES' do
        expect(EE::Authz::RedactionService::EE_RESOURCE_CLASSES[:group]).to eq(::Group)
      end

      it 'includes saml_provider in EE preload associations for group' do
        expect(EE::Authz::RedactionService::EE_PRELOAD_ASSOCIATIONS[:group]).to include(:saml_provider)
      end

      it 'includes system_note_metadata in EE preload associations for notes' do
        expect(EE::Authz::RedactionService::EE_PRELOAD_ASSOCIATIONS[:note]).to include(:system_note_metadata)
      end
    end
  end
end
