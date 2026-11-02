# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NoteEntity do
  include Gitlab::Routing

  let_it_be(:issue, freeze: false) { create(:issue) }
  let_it_be(:description_version) { create(:description_version, issue: issue) }
  let_it_be(:system_note_metadata, freeze: false) { create(:system_note_metadata, description_version: description_version) }
  let_it_be(:system_note, freeze: false) do
    create(:system_note, project: issue.project, noteable: issue, system_note_metadata: system_note_metadata)
  end

  let_it_be(:plain_note, refind: true) do
    create(:note, project: issue.project, noteable: issue)
  end

  let_it_be(:outsider) { create(:user) }

  let(:note) { plain_note }
  let(:request) { double('request', current_user: issue.author, noteable: issue) }
  let(:entity) { described_class.new(note, request: request) }

  subject { entity.as_json }

  describe 'duo session fields on non-system notes', feature_category: :duo_agent_platform do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: issue.project, environment: :web) }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    context 'when the note has a triggered workflow link' do
      let_it_be(:triggering_note) { create(:note, project: issue.project, noteable: issue) }
      let(:note) { triggering_note }

      before_all do
        create(:duo_workflows_workflow_note, workflow: workflow, note: triggering_note, link_type: :triggered)
      end

      it 'exposes duo session fields from the triggered workflow', :aggregate_failures do
        presenter = ::Ai::DuoWorkflows::WorkflowPresenter.new(workflow)

        expect(subject[:duo_session_id_triggered]).to eq(workflow.to_global_id)
        expect(subject[:duo_session_agent_name]).to eq(presenter.agent_name)
        expect(subject[:duo_session_status]).to eq(workflow.status_name)
        expect(subject[:duo_session_status]).not_to eq(workflow.status)
      end

      context 'when the current user cannot read the triggered workflow' do
        let(:request) { double('request', current_user: outsider, noteable: issue) }

        it 'omits all triggered duo session fields', :aggregate_failures do
          expect(subject[:duo_session_id_triggered]).to be_nil
          expect(subject[:duo_session_agent_name]).to be_nil
          expect(subject[:duo_session_status]).to be_nil
        end
      end
    end

    context 'when the note has no triggered workflow link' do
      it 'exposes duo session fields as nil for a plain note', :aggregate_failures do
        expect(subject[:duo_session_id_triggered]).to be_nil
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end

      context 'when the note has a created (agent-reply) link instead' do
        let_it_be(:reply_note) { create(:note, project: issue.project, noteable: issue) }
        let(:note) { reply_note }

        before_all do
          create(:duo_workflows_workflow_note, workflow: workflow, note: reply_note, link_type: :created)
        end

        it 'exposes duo session fields as nil', :aggregate_failures do
          expect(subject[:duo_session_id_triggered]).to be_nil
          expect(subject[:duo_session_agent_name]).to be_nil
          expect(subject[:duo_session_status]).to be_nil
        end
      end
    end

    context 'when the note is a system note' do
      let(:note) { system_note }

      it 'omits all duo session fields', :aggregate_failures do
        expect(subject.key?(:duo_session_id_triggered)).to be false
        expect(subject.key?(:duo_session_agent_name)).to be false
        expect(subject.key?(:duo_session_status)).to be false
      end
    end
  end

  describe 'duo_session_id', feature_category: :duo_agent_platform do
    # Note-triggered flows run in the web environment, which WorkflowPolicy treats as
    # from_pipeline? and grants to any project member with Duo access.
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: issue.project, environment: :web)
    end

    let_it_be(:duo_metadata) do
      create(:note_duo_metadata, note: plain_note, workflow_id: workflow.id, namespace_id: issue.namespace_id)
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    context 'when the current user cannot read the session' do
      let(:request) { double('request', current_user: outsider, noteable: issue) }

      it 'omits duo_session_id so the frontend does not offer a session it cannot open' do
        expect(subject.key?(:duo_session_id)).to be false
      end

      context 'when the note is linked through a created workflow_note' do
        let_it_be(:unauthorized_linked_note) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { unauthorized_linked_note }

        before_all do
          ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
            workflow: workflow, artifact: unauthorized_linked_note, link_type: :created
          )
        end

        it 'omits duo_session_id' do
          expect(subject.key?(:duo_session_id)).to be false
        end
      end
    end

    context 'when there is no current user' do
      let(:request) { double('request', current_user: nil, noteable: issue) }

      it 'omits duo_session_id for anonymous users' do
        expect(subject.key?(:duo_session_id)).to be false
      end
    end

    context 'when the note is not a system note' do
      it 'exposes the workflow id as duo_session_id' do
        expect(subject[:duo_session_id]).to eq(workflow.id)
      end

      context 'when the note has no duo_metadata' do
        let_it_be(:note_without_metadata) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { note_without_metadata }

        it 'exposes duo_session_id as nil' do
          expect(subject[:duo_session_id]).to be_nil
        end

        it 'omits the key entirely rather than sending null on every note' do
          expect(subject.key?(:duo_session_id)).to be false
        end
      end

      context 'when the note is linked to a workflow through a created workflow_note' do
        let_it_be(:linked_note) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { linked_note }

        before_all do
          ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
            workflow: workflow, artifact: linked_note, link_type: :created
          )
        end

        it 'falls back to the linked workflow id' do
          expect(subject[:duo_session_id]).to eq(workflow.id)
        end
      end

      context 'when the note was created by an automated code review session' do
        let_it_be(:code_review_workflow) do
          create(:duo_workflows_workflow, project: issue.project, environment: :web,
            workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
        end

        let_it_be(:review_note) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { review_note }

        before_all do
          ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
            workflow: code_review_workflow, artifact: review_note, link_type: :created
          )
        end

        it 'exposes the linked workflow id' do
          expect(subject[:duo_session_id]).to eq(code_review_workflow.id)
        end

        context 'when agent_presence_consolidation is disabled' do
          before do
            stub_feature_flags(agent_presence_consolidation: false)
          end

          it 'omits duo_session_id so the per-comment session link stays hidden' do
            expect(subject.key?(:duo_session_id)).to be false
          end

          context 'when the note also has duo_metadata' do
            let_it_be(:summary_metadata) do
              create(:note_duo_metadata, note: review_note, workflow_id: code_review_workflow.id,
                namespace_id: issue.namespace_id)
            end

            it 'still exposes the workflow id from the metadata' do
              expect(subject[:duo_session_id]).to eq(code_review_workflow.id)
            end
          end

          context 'when the session is not a code review flow' do
            let_it_be(:other_flow_note) { create(:note, project: issue.project, noteable: issue) }

            let(:note) { other_flow_note }

            before_all do
              ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
                workflow: workflow, artifact: other_flow_note, link_type: :created
              )
            end

            it 'exposes the linked workflow id' do
              expect(subject[:duo_session_id]).to eq(workflow.id)
            end
          end

          context 'when the session is a @GitLabDuo conversation' do
            let_it_be(:conversation_workflow) do
              create(:duo_workflows_workflow, project: issue.project, environment: :web,
                workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference,
                messaging_callback_context: { 'adapter' => 'gitlab_duo_note' })
            end

            let_it_be(:conversation_note) { create(:note, project: issue.project, noteable: issue) }

            let(:note) { conversation_note }

            before_all do
              ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
                workflow: conversation_workflow, artifact: conversation_note, link_type: :created
              )
            end

            it 'exposes the linked workflow id' do
              expect(subject[:duo_session_id]).to eq(conversation_workflow.id)
            end
          end
        end
      end
    end

    context 'when the note is a system note' do
      let(:note) { system_note }

      it 'does not expose duo_session_id' do
        expect(subject.key?(:duo_session_id)).to be false
      end
    end

    context 'when the note is a duo_mention_started system note' do
      let_it_be(:duo_mention_note) do
        create(:system_note, project: issue.project, noteable: issue,
          system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
      end

      let_it_be(:duo_mention_metadata) do
        create(:note_duo_metadata, note: duo_mention_note, workflow_id: workflow.id,
          namespace_id: issue.namespace_id)
      end

      let(:note) { duo_mention_note }

      it 'exposes the workflow id as duo_session_id' do
        expect(subject[:duo_session_id]).to eq(workflow.id)
      end
    end
  end

  describe 'duo session fields on duo_mention_started system notes', feature_category: :dap_code_review do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: issue.project, environment: :web) }

    # Use a dedicated system note so we don't conflict with the top-level
    # system_note_metadata (which already occupies the unique slot on system_note).
    let_it_be(:duo_mention_note) do
      create(:system_note, project: issue.project, noteable: issue,
        system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
    end

    let(:note) { duo_mention_note }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    before_all do
      create(:note_duo_metadata, note: duo_mention_note, workflow_id: workflow.id,
        namespace_id: issue.namespace_id)
    end

    it 'exposes duo session fields from the linked workflow', :aggregate_failures do
      presenter = ::Ai::DuoWorkflows::WorkflowPresenter.new(workflow)

      expect(subject[:duo_session_id]).to eq(workflow.id)
      expect(subject[:duo_session_agent_name]).to eq(presenter.agent_name)
      expect(subject[:duo_session_status]).to eq(workflow.status_name)
      expect(subject[:duo_session_status]).not_to eq(workflow.status)
    end

    context 'when the current user cannot read the workflow' do
      let(:request) { double('request', current_user: outsider, noteable: issue) }

      it 'omits duo session fields', :aggregate_failures do
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end
    end

    context 'when the duo_mention_started note has no duo_metadata' do
      let_it_be(:bare_duo_mention_note) do
        create(:system_note, project: issue.project, noteable: issue,
          system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
      end

      let(:note) { bare_duo_mention_note }

      it 'exposes duo session fields as nil', :aggregate_failures do
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end
    end

    context 'when the system note has a different action' do
      let(:note) { system_note }

      it 'omits all duo session fields', :aggregate_failures do
        expect(subject.key?(:duo_session_id)).to be false
        expect(subject.key?(:duo_session_agent_name)).to be false
        expect(subject.key?(:duo_session_status)).to be false
      end
    end
  end

  describe 'agent_presence', feature_category: :duo_agent_platform do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: issue.project, user: issue.author) }

    before do
      stub_feature_flags(agent_presence_consolidation: issue.project.root_ancestor)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
    end

    it 'is nil when no session posted the note' do
      expect(subject).to include(agent_presence: nil)
    end

    context 'when a session posted the note through the API' do
      let_it_be(:api_note) { create(:note, project: issue.project, noteable: issue) }
      let(:note) { api_note }

      before_all do
        create(:duo_workflows_workflow_note, workflow: workflow, note: api_note, link_type: :created)
      end

      it 'exposes the session that created the note' do
        expect(subject[:agent_presence]).to include(session_id: workflow.id)
      end

      context 'when the viewer cannot read the session' do
        let(:request) { EntityRequest.new(current_user: outsider, noteable: issue) }

        it 'still exposes the presence but reports the session as not readable' do
          expect(subject[:agent_presence]).to include(
            session_id: workflow.id,
            user_permissions: { read_duo_workflow: false }
          )
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agent_presence_consolidation: false)
        end

        it 'omits agent_presence' do
          expect(subject).not_to have_key(:agent_presence)
        end
      end
    end

    context 'when Duo Code Review posted the note' do
      let_it_be(:review_note) { create(:note, project: issue.project, noteable: issue) }
      let_it_be(:review_workflow) { create(:duo_workflows_workflow, project: issue.project, user: issue.author) }
      let(:note) { review_note }

      before_all do
        create(:note_duo_metadata, note: review_note, workflow_id: review_workflow.id,
          namespace_id: issue.namespace_id)
        create(:duo_workflows_workflow_note, workflow: workflow, note: review_note, link_type: :created)
      end

      it 'prefers the duo_metadata session' do
        expect(subject[:agent_presence]).to include(session_id: review_workflow.id)
      end
    end

    context 'when the note only has duo_metadata' do
      let_it_be(:metadata_note) { create(:note, project: issue.project, noteable: issue) }
      let(:note) { metadata_note }

      before_all do
        create(:note_duo_metadata, note: metadata_note, workflow_id: workflow.id, namespace_id: issue.namespace_id)
      end

      it 'exposes the duo_metadata session' do
        expect(subject[:agent_presence]).to include(session_id: workflow.id)
      end
    end

    context 'when the note only triggered a session' do
      let_it_be(:triggering_note) { create(:note, project: issue.project, noteable: issue) }
      let(:note) { triggering_note }

      before_all do
        create(:duo_workflows_workflow_note, workflow: workflow, note: triggering_note, link_type: :triggered)
      end

      it 'is nil' do
        expect(subject).to include(agent_presence: nil)
      end
    end

    context 'when the note is a system note' do
      let(:note) { system_note }

      it 'omits agent_presence' do
        expect(subject).not_to have_key(:agent_presence)
      end
    end

    context 'when the note has no project or namespace' do
      let_it_be(:personal_snippet_note) { create(:note_on_personal_snippet) }
      let(:note) { personal_snippet_note }
      let(:request) { EntityRequest.new(current_user: note.author, noteable: note.noteable) }

      it 'omits agent_presence without checking the feature flag' do
        expect(::Feature).not_to receive(:enabled?).with(:agent_presence_consolidation, anything)

        expect(subject).not_to have_key(:agent_presence)
      end
    end
  end

  describe 'duo_code_review_finding', feature_category: :dap_code_review do
    context 'when the note has a stored finding' do
      let_it_be(:finding) { create(:duo_code_review_finding, severity: :major, depth: :deep, category: 'logic-error') }
      let(:note) { finding.note }

      it 'exposes the classification without the confidence' do
        expect(subject[:duo_code_review_finding])
          .to eq('severity' => 'major', 'category' => 'logic-error', 'depth' => 'deep')
      end
    end

    context 'when the note has no stored finding' do
      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding)
      end
    end

    context 'when the note is not on a merge request' do
      it 'does not query findings' do
        expect { subject }.not_to exceed_query_limit(0).for_model(Ai::DuoWorkflows::CodeReview::Finding)
      end
    end
  end

  describe 'duo_code_review_finding_note_ids', feature_category: :dap_code_review do
    let_it_be(:merge_request) { create(:merge_request) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: merge_request.project) }
    let_it_be(:finding_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: merge_request.project) }
    let_it_be(:finding) { create(:duo_code_review_finding, note: finding_note, workflow: workflow) }
    let_it_be(:earlier_attempt_note) do
      create(:note, project: merge_request.project, noteable: merge_request, created_at: finding.created_at - 1.minute)
    end

    let_it_be(:summary_note) do
      create(:note, project: merge_request.project, noteable: merge_request, created_at: finding.created_at - 1.second)
    end

    let(:request) { double('request', current_user: merge_request.author, noteable: merge_request) }

    before_all do
      [finding_note, earlier_attempt_note, summary_note].each do |linked_note|
        Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: workflow, artifact: linked_note, link_type: :created)
      end
    end

    context 'when the note is the summary of a review that stored findings' do
      let(:note) { summary_note }

      it 'exposes the note ids of the review findings' do
        expect(subject[:duo_code_review_finding_note_ids]).to eq([finding.note_id.to_s])
      end
    end

    context 'when the note was left by an earlier attempt that a retry completed' do
      let(:note) { earlier_attempt_note }

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end

    context 'when the review posts another note after storing its findings' do
      let(:note) do
        create(:note, project: merge_request.project, noteable: merge_request, created_at: finding.created_at + 1.second)
      end

      before do
        Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: workflow, artifact: note, link_type: :created)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end

    context 'when the review posted no note before storing its findings' do
      let(:other_workflow) { create(:duo_workflows_workflow, project: merge_request.project) }
      let(:other_finding_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: merge_request.project) }
      let(:other_finding) { create(:duo_code_review_finding, note: other_finding_note, workflow: other_workflow) }
      let(:note) do
        create(:note, project: merge_request.project, noteable: merge_request, created_at: other_finding.created_at + 1.second)
      end

      before do
        Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: other_workflow, artifact: note, link_type: :created)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end

    context 'when the note is a finding of the review' do
      let(:note) { finding_note }

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end

    context 'when the review stored no findings' do
      let(:note) { create(:note, project: merge_request.project, noteable: merge_request) }

      before do
        other_workflow = create(:duo_workflows_workflow, project: merge_request.project)
        Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: other_workflow, artifact: note, link_type: :created)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end

    context 'when the note is not linked to a review' do
      let(:note) { create(:note, project: merge_request.project, noteable: merge_request) }

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_finding_note_ids)
      end
    end
  end

  describe 'duo_code_review_depth', feature_category: :dap_code_review do
    let_it_be(:merge_request) { create(:merge_request) }
    let_it_be(:requester) { create(:user) }
    let_it_be(:workflow, freeze: false) do
      create(:duo_workflows_workflow, project: merge_request.project, user: requester,
        flow_metadata_json: { flow_id: 'deep_code_review' }.to_json)
    end

    let_it_be(:summary_note, refind: true) { create(:note, project: merge_request.project, noteable: merge_request) }

    let(:request) { double('request', current_user: merge_request.author, noteable: merge_request) }
    let(:note) { summary_note }

    before_all do
      Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: workflow, artifact: summary_note, link_type: :created)
    end

    before do
      stub_feature_flags(duo_code_review_deep_flow: requester, duo_code_review_standard_structured_findings: false)
    end

    it 'exposes the depth of the flow that ran' do
      expect(subject[:duo_code_review_depth]).to eq('deep')
    end

    context 'when the standard flow ran' do
      before do
        workflow.update!(flow_metadata_json: { flow_id: 'code_review' }.to_json)
        stub_feature_flags(duo_code_review_deep_flow: false, duo_code_review_standard_structured_findings: requester)
      end

      it 'exposes the standard depth' do
        expect(subject[:duo_code_review_depth]).to eq('standard')
      end
    end

    context 'when structured findings are disabled for the requester' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: false)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_depth)
      end
    end

    context 'when the workflow has not recorded which flow ran' do
      before do
        workflow.update!(flow_metadata_json: nil)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_depth)
      end
    end

    context 'when the review stored findings' do
      before do
        finding_note = create(:diff_note_on_merge_request, noteable: merge_request, project: merge_request.project)
        create(:duo_code_review_finding, note: finding_note, workflow: workflow)
      end

      it 'still exposes the depth for the summary card' do
        expect(subject).to have_key(:duo_code_review_finding_note_ids)
        expect(subject[:duo_code_review_depth]).to eq('deep')
      end
    end

    context 'when the note is a diff note' do
      let(:note) { create(:diff_note_on_merge_request, noteable: merge_request, project: merge_request.project) }

      before do
        Ai::DuoWorkflows::WorkflowNote.ensure_link(workflow: workflow, artifact: note, link_type: :created)
      end

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_depth)
      end
    end

    context 'when the note is not linked to a review' do
      let(:note) { create(:note, project: merge_request.project, noteable: merge_request) }

      it 'does not expose the field' do
        expect(subject).not_to have_key(:duo_code_review_depth)
      end
    end
  end

  describe 'description versions', feature_category: :team_planning do
    let(:note) { system_note }

    context 'when description_diffs license is available' do
      before do
        stub_licensed_features(description_diffs: true)
      end

      it 'includes description versions attributes' do
        expect(subject[:description_version_id]).to eq(description_version.id)
        expect(subject[:description_diff_path]).to eq(description_diff_project_issue_path(issue.project, issue, description_version.id))
        expect(subject[:delete_description_version_path]).to eq(delete_description_version_project_issue_path(issue.project, issue, description_version.id))
        expect(subject[:can_delete_description_version]).to be(true)
      end
    end

    context 'when description_diffs license is not available' do
      before do
        stub_licensed_features(description_diffs: false)
      end

      it 'does not include description versions attributes' do
        expect(subject[:description_version_id]).to be_nil
        expect(subject[:description_diff_path]).to be_nil
        expect(subject[:delete_description_version_path]).to be_nil
        expect(subject[:can_delete_description_version]).to be_nil
      end
    end
  end
end
