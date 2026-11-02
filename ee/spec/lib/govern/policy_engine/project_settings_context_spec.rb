# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ProjectSettingsContext, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) do
    create(:project, group: group, visibility_level: Gitlab::VisibilityLevel::PRIVATE)
  end

  let_it_be(:actor) { create(:user) }

  subject(:context) do
    described_class.build(project: project, trigger: 'project.before_settings_update', actor: actor)
  end

  it 'carries the envelope and scope dimensions the scope rego reads' do
    expect(context['schema_version']).to eq('1-0-1')
    expect(context['trigger']).to eq('project.before_settings_update')
    expect(context['actor']).to eq("users/#{actor.id}")
    expect(context['organization']).to eq('id' => "organizations/#{project.organization_id}")
    expect(context['groups']).to eq([group.id])
    expect(context['compliance_frameworks']).to eq([])
    expect(context.dig('project', 'id')).to eq(project.id)
    expect(context.dig('project', 'personal')).to be(false)
    expect(context.dig('project', 'archived')).to be(false)
  end

  describe '.settings_for' do
    it 'returns the settings map of the full document' do
      expect(described_class.settings_for(project)).to eq(context.dig('project', 'settings'))
    end
  end

  it 'maps raw scalar settings by catalog key' do
    settings = context.dig('project', 'settings')

    expect(settings['visibility']).to eq('private')
    expect(settings['request_access_enabled']).to eq(project.read_attribute(:request_access_enabled))
    expect(settings['squash_option']).to eq(project.project_setting.squash_option)
    expect(settings['keep_latest_artifact']).to eq(project.ci_cd_settings.read_attribute(:keep_latest_artifact))
    expect(settings['merge_requests_access_level']).to eq('enabled')
  end

  # Once the settings catalog of
  # https://gitlab.com/gitlab-org/gitlab/-/work_items/630152 ships, this
  # pinned list becomes a comparison against the catalog.
  it 'emits exactly the governable project settings' do
    stub_licensed_features(secret_push_protection: true)

    expect(context.dig('project', 'settings').keys).to match_array(%w[
      visibility request_access_enabled only_allow_merge_if_pipeline_succeeds
      only_allow_merge_if_all_discussions_are_resolved remove_source_branch_after_merge
      squash_option allow_author_approval allow_committer_approval
      allow_overrides_to_approver_list_per_merge_request retain_approvals_on_push
      keep_latest_artifact allow_fork_pipelines_to_run_in_parent_project
      pipeline_variables_minimum_override_role merge_requests_access_level
      builds_access_level forking_access_level secret_push_protection_enabled
    ])
  end

  it 'omits license-gated settings the tier does not license, even though the row exists' do
    stub_licensed_features(secret_push_protection: false)

    expect(project.security_setting).to be_present
    expect(context.dig('project', 'settings')).not_to have_key('secret_push_protection_enabled')
  end

  it 'omits license-gated settings whose storage row is absent' do
    stub_licensed_features(secret_push_protection: true)
    # Projects that predate the row-creating callback can lack the row.
    allow(project).to receive(:security_setting).and_return(nil)

    expect(context.dig('project', 'settings')).not_to have_key('secret_push_protection_enabled')
  end

  it 'omits squash_option when its column is NULL' do
    project.project_setting.update!(squash_option: nil)

    expect(context.dig('project', 'settings')).not_to have_key('squash_option')
  end

  it 'keeps a NULL remove_source_branch_after_merge, which the schema models as nullable' do
    project.update_column(:remove_source_branch_after_merge, nil)

    expect(context.dig('project', 'settings')).to have_key('remove_source_branch_after_merge')
    expect(context.dig('project', 'settings', 'remove_source_branch_after_merge')).to be_nil
  end

  it 'omits the CI/CD and feature families when their storage rows are absent' do
    allow(project).to receive_messages(ci_cd_settings: nil, project_feature: nil)

    settings = context.dig('project', 'settings')

    expect(settings).not_to have_key('keep_latest_artifact')
    expect(settings).not_to have_key('merge_requests_access_level')
  end

  it 'reports no groups for a personal project' do
    personal_project = create(:project)

    personal_context = described_class.build(project: personal_project,
      trigger: 'project.before_settings_update', actor: actor)

    expect(personal_context['groups']).to eq([])
    expect(personal_context.dig('project', 'personal')).to be(true)
  end

  describe 'the MR-approval family' do
    it 'reads the OWN columns even when an instance-level prevention would win at resolution time' do
      stub_licensed_features(admin_merge_request_approvers_rules: true)
      stub_ee_application_setting(prevent_merge_requests_author_approval: true)
      project.update_column(:merge_requests_author_approval, true)

      # Compliance runs against the stored value, so a project that is
      # compliant only through an upper level still gets converged.
      expect(context.dig('project', 'settings', 'allow_author_approval')).to be(true)
    end

    it 'inverts the disable-term columns into allow-terms' do
      project.update_column(:merge_requests_disable_committers_approval, true)

      expect(context.dig('project', 'settings', 'allow_committer_approval')).to be(false)
    end

    it 'reads a NULL column as no restriction, so both entry kinds allow' do
      project.update_column(:merge_requests_author_approval, nil)
      project.update_column(:merge_requests_disable_committers_approval, nil)

      settings = context.dig('project', 'settings')

      expect(settings['allow_author_approval']).to be(true)
      expect(settings['allow_committer_approval']).to be(true)
    end
  end

  it 'validates against the GLAZ project settings context schema' do
    # The fixture is a vendored copy of glaz:govern:context:project_settings:1-0-1
    # (crates/glaz-govern/src/schemas/), so the spec needs no GLAZ checkout.
    schema = JSONSchemer.schema(
      Rails.root.join('ee/spec/fixtures/govern/project_settings_context_schema.json'))
    errors = schema.validate(Gitlab::Json::SafeParser.parse(context.to_json))
      .map { |e| e.fetch('error') }

    expect(errors).to be_empty
  end
end
