# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::BlSecurityContextBuilder, feature_category: :duo_agent_platform do
  include ProjectForksHelper

  let(:schema_path) do
    Rails.root.join('app/validators/json_schemas/agent_platform/agent_platform_bl_security_context/1.0.0.json')
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  let_it_be(:project) { create(:project, :repository) }

  let(:workflow_definition) { ::Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE }
  let(:goal) { nil }
  let(:primary_branch) { project.default_branch_or_main }

  subject(:fields) do
    described_class.build(
      project: project,
      workflow_definition: workflow_definition,
      goal: goal,
      primary_branch: primary_branch
    )
  end

  shared_examples 'a schema-conformant context' do
    it 'is valid against the schema' do
      expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
    end
  end

  shared_examples 'no context' do
    it 'returns nil without reading the variables' do
      expect(project).not_to receive(:variables)

      expect(fields).to be_nil
    end
  end

  it 'names its category' do
    expect(described_class::CATEGORY).to eq('agent_platform_bl_security_context')
  end

  describe 'gating' do
    before do
      create(:ci_variable, project: project, key: 'BL_SCAN_EFFORT', value: 'high')
      create(:ci_variable, project: project, key: 'BL_TARGET_FILES', value: 'lib/')
    end

    context 'when the flag is enabled and the run checks out a non-default branch' do
      let(:primary_branch) { 'feature' }

      include_examples 'a schema-conformant context'

      it 'includes both dials' do
        expect(fields).to eq("scan_effort" => 'high', "target_files" => 'lib/')
      end

      it 'ignores a duplicate key scoped to a specific environment' do
        create(:ci_variable, project: project, key: 'BL_SCAN_EFFORT', value: 'low', environment_scope: 'production')

        expect(fields).to include("scan_effort" => 'high')
      end
    end

    context 'when the workflow is not the business logic security scan flow' do
      let(:workflow_definition) { 'developer/v1' }

      include_examples 'no context'
    end

    context 'when the bl_security_analyzer feature flag is disabled' do
      before do
        stub_feature_flags(bl_security_analyzer: false)
      end

      include_examples 'no context'

      context 'on GitLab Dedicated with the instance beta setting on', :dedicated do
        before do
          stub_application_setting(instance_level_ai_beta_features_enabled: true)
          allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
            .with('bl_security').and_return(true)
        end

        it 'reads the dials' do
          expect(fields).to include("scan_effort" => 'high')
        end

        context 'when GitLab has not enabled the flow for the instance' do
          before do
            allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
              .with('bl_security').and_return(false)
          end

          include_examples 'no context'
        end
      end
    end
  end

  describe 'variables that are protected or file-typed' do
    let(:primary_branch) { 'feature' }

    where(:trait) { [:protected, :file] }

    with_them do
      it 'ignores them' do
        create(:ci_variable, trait, project: project, key: 'BL_SCAN_EFFORT', value: 'high')
        create(:ci_variable, trait, project: project, key: 'BL_TARGET_FILES', value: 'lib/')

        expect(fields).to eq("scan_effort" => 'low')
      end
    end
  end

  describe 'scan_effort' do
    include_examples 'a schema-conformant context'

    it 'defaults to low when BL_SCAN_EFFORT is unset' do
      expect(fields).to eq("scan_effort" => 'low')
    end

    it 'defaults to low when BL_SCAN_EFFORT is blank' do
      create(:ci_variable, project: project, key: 'BL_SCAN_EFFORT', value: '')

      expect(fields["scan_effort"]).to eq('low')
    end

    where(:value, :expected) do
      [
        %w[low low],
        %w[standard standard],
        %w[high high],
        %w[High high],
        [' STANDARD ', 'standard']
      ]
    end

    with_them do
      it 'sends a known BL_SCAN_EFFORT normalized' do
        create(:ci_variable, project: project, key: 'BL_SCAN_EFFORT', value: value)

        expect(::Gitlab::AppJsonLogger).not_to receive(:info)
        expect(fields["scan_effort"]).to eq(expected)
        expect(schema.valid?(fields)).to be(true)
      end
    end

    it 'sends low and logs once when BL_SCAN_EFFORT is not a known tier' do
      create(:ci_variable, project: project, key: 'BL_SCAN_EFFORT', value: 'maximum')

      expect(::Gitlab::AppJsonLogger).to receive(:info).once.with(
        hash_including(project_id: project.id, reason: 'invalid_scan_effort')
      )
      expect(fields["scan_effort"]).to eq('low')
      expect(schema.valid?(fields)).to be(true)
    end
  end

  describe 'target_files when the goal is a merge request IID' do
    let_it_be(:merge_request) { create(:merge_request, :simple, source_project: project) }

    let(:goal) { merge_request.iid.to_s }
    let(:primary_branch) { merge_request.source_branch }
    let(:target_files_class) { ::Ai::Catalog::FoundationalFlow::BlSecurity::TargetFiles }
    let(:changed_paths) do
      merge_request.merge_request_diff.merge_request_diff_files.reject(&:deleted_file).map(&:new_path)
    end

    def stub_target_files(paths, reason, source_branch = nil)
      allow(target_files_class).to receive(:for_goal).with(project: project, goal: goal)
        .and_return(target_files_class::Result.new(paths, reason, source_branch))
    end

    include_examples 'a schema-conformant context'

    it 'lists the files the merge request adds or modifies, one per line' do
      expect(changed_paths).not_to be_empty
      expect(fields["target_files"]).to eq(changed_paths.join("\n"))
    end

    context 'when BL_TARGET_FILES is set' do
      before do
        create(:ci_variable, project: project, key: 'BL_TARGET_FILES', value: 'lib/')
      end

      it 'uses the variable and does not read the diff' do
        expect(target_files_class).not_to receive(:for_goal)

        expect(fields["target_files"]).to eq('lib/')
      end
    end

    where(reason: [
      :diff_overflow, :too_many_paths, :diff_not_collected, :merge_request_not_found, :unsupported_path,
      :fork_merge_request
    ])

    with_them do
      before do
        stub_target_files(nil, reason)
      end

      it 'omits target_files and logs why' do
        allow(::Gitlab::AppJsonLogger).to receive(:info)
        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(project_id: project.id, merge_request_iid: goal, reason: reason.to_s)
        )

        expect(fields.keys).not_to include("target_files")
        expect(schema.valid?(fields)).to be(true)
      end
    end

    context 'when the run checks out a branch other than the merge request source branch' do
      let(:primary_branch) { 'other-branch' }

      it 'omits target_files and logs the branch mismatch' do
        allow(::Gitlab::AppJsonLogger).to receive(:info)
        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(project_id: project.id, merge_request_iid: goal, reason: 'branch_mismatch')
        )

        expect(fields.keys).not_to include("target_files")
        expect(schema.valid?(fields)).to be(true)
      end

      context 'when BL_TARGET_FILES is set' do
        before do
          create(:ci_variable, project: project, key: 'BL_TARGET_FILES', value: 'lib/')
        end

        it 'uses the variable' do
          expect(fields["target_files"]).to eq('lib/')
        end
      end
    end

    context 'when the merge request is from a fork' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be(:fork_merge_request) do
        create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
      end

      let(:goal) { fork_merge_request.iid.to_s }
      let(:primary_branch) { fork_merge_request.source_branch }

      it 'omits target_files and logs why' do
        allow(::Gitlab::AppJsonLogger).to receive(:info)
        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(project_id: project.id, merge_request_iid: goal, reason: 'fork_merge_request')
        )

        expect(fields.keys).not_to include("target_files")
      end
    end

    context 'when the run checks out the default branch' do
      let(:primary_branch) { project.default_branch_or_main }

      it 'scans the whole repository and does not read the diff' do
        expect(target_files_class).not_to receive(:for_goal)

        expect(fields.keys).not_to include("target_files")
      end

      context 'when BL_TARGET_FILES is set' do
        before do
          create(:ci_variable, project: project, key: 'BL_TARGET_FILES', value: 'lib/')
        end

        it 'ignores the variable and scans the whole repository' do
          expect(fields.keys).not_to include("target_files")
        end
      end
    end

    context 'when the goal is a URL rather than a merge request IID' do
      let(:goal) { 'http://example.com/pipelines/1' }

      it 'omits target_files without logging' do
        expect(::Gitlab::AppJsonLogger).not_to receive(:info).with(hash_including(message: /target_files omitted/))

        expect(fields.keys).not_to include("target_files")
      end
    end
  end

  describe 'schema' do
    it 'rejects fields outside the category' do
      expect(schema.valid?({ "scan_effort" => 'low', "primary_branch" => 'main' })).to be(false)
    end

    it 'rejects an unknown scan_effort tier' do
      expect(schema.valid?({ "scan_effort" => 'maximum' })).to be(false)
    end

    it 'requires scan_effort' do
      expect(schema.valid?({ "target_files" => 'lib/' })).to be(false)
    end
  end
end
