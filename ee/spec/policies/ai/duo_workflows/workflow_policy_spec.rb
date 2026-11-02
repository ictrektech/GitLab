# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowPolicy, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  subject(:policy) { described_class.new(current_user, workflow) }

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, project: project, environment: :ide) }
  let_it_be(:guest) { create(:user, guest_of: workflow.project) }
  let_it_be(:developer) { create(:user, developer_of: workflow.project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: workflow.project) }
  let_it_be(:composite_service_account) do
    create(:user, :service_account, developer_of: project, composite_identity_enforced: true)
  end

  let(:current_user) { developer }

  describe "read_duo_workflow and update_duo_workflow" do
    where(:duo_features_enabled, :current_user, :stage_check_available, :user_is_allowed_to_use, :allowed) do
      true   | ref(:developer)  | true  | false | false
      true   | ref(:developer)  | false | false | false
      true   | ref(:maintainer) | false | false | false
      true   | ref(:maintainer) | true  | false | false
      true   | ref(:guest)      | true  | false | false
      false  | ref(:developer)  | true  | false | false
      true   | ref(:maintainer) | true  | true  | true
      true   | ref(:guest)      | true  | true  | false
      true   | ref(:developer)  | true  | true  | true
    end

    with_them do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
          :duo_workflow).and_return(stage_check_available)
        allow(current_user).to receive(:allowed_to_use?).and_return(user_is_allowed_to_use)
        project.project_setting.update!(duo_features_enabled: duo_features_enabled)
        workflow.update!(user: current_user)
      end

      it 'checks read and update workflow policy' do
        is_expected.to(allowed ? be_allowed(:read_duo_workflow) : be_disallowed(:read_duo_workflow))
        is_expected.to(allowed ? be_allowed(:update_duo_workflow) : be_disallowed(:update_duo_workflow))
      end
    end

    context "when user is not workflow owner but has project access and workflow is non-chat web environment" do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        project.project_setting.update!(duo_features_enabled: true)
        workflow.update!(user: maintainer, environment: :web)
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
      end

      it { expect_allowed(:read_duo_workflow) }
      it { expect_disallowed(:update_duo_workflow) }
    end

    context "when user is not workflow owner but has project access and workflow is non-chat ambient environment" do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        project.project_setting.update!(duo_features_enabled: true)
        workflow.update!(user: maintainer, environment: :ambient)
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
      end

      it { expect_allowed(:read_duo_workflow) }
      it { expect_disallowed(:update_duo_workflow) }
    end

    context "when user is not workflow owner" do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        project.project_setting.update!(duo_features_enabled: true)
        workflow.update!(user: maintainer, environment: :ide)
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
      end

      it { expect_disallowed(:read_duo_workflow) }
      it { expect_disallowed(:update_duo_workflow) }

      context "when current user is a service account" do
        let(:current_user) { composite_service_account }

        before do
          allow(current_user).to receive(:allowed_to_use?).and_return(true)
        end

        it { expect_allowed(:read_duo_workflow) }
        it { expect_allowed(:update_duo_workflow) }
        it { expect_disallowed(:resume_duo_workflow) }

        context 'when workflow is in input_required state' do
          before do
            pipeline = create(:ci_pipeline, :success, project: project)
            workload = create(:ci_workload, pipeline: pipeline, project: project)
            workflow.workflows_workloads.create!(workload: workload, project: project)
            workflow.update!(status: status_enum(:input_required))
          end

          it { expect_allowed(:resume_duo_workflow) }
        end
      end

      context "when current user is a regular service account (not AI service account)" do
        let(:current_user) { create(:user, :service_account, developer_of: workflow.project) }

        before do
          allow(current_user).to receive(:allowed_to_use?).and_return(true)
        end

        it { expect_disallowed(:read_duo_workflow) }
        it { expect_disallowed(:update_duo_workflow) }
      end
    end

    context 'when a Reporter owns a client-executed project session' do
      let_it_be(:reporter) { create(:user, reporter_of: project) }

      let(:current_user) { reporter }

      before do
        workflow.update!(user: current_user, execution_mode: :client)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(false)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(true)
        allow(current_user).to receive(:allowed_to_use_for_resource?).and_return(true)
      end

      it 'lets the owner read and update the session', :aggregate_failures do
        expect_allowed(:read_duo_workflow)
        expect_allowed(:update_duo_workflow)
      end

      it 'keeps remote execution denied when remote flows are enabled' do
        project.project_setting.update!(duo_remote_flows_enabled: true)

        expect_disallowed(:execute_duo_workflow_in_ci)
      end

      context 'when Duo Workflow is also available in the project' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          project.project_setting.update!(duo_remote_flows_enabled: true)
        end

        it 'lets the owner read and update the session', :aggregate_failures do
          expect_allowed(:read_duo_workflow)
          expect_allowed(:update_duo_workflow)
        end

        # update_duo_workflow alone must not unlock CI execution for roles below Developer
        it 'keeps remote execution denied' do
          expect_disallowed(:execute_duo_workflow_in_ci)
        end
      end

      context 'when Agentic Chat is unavailable in the project' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(false)
        end

        it 'does not allow access to the session', :aggregate_failures do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end

      it 'keeps resume denied when the workflow is otherwise resumable' do
        pipeline = create(:ci_pipeline, :success, project: project)
        workload = create(:ci_workload, pipeline: pipeline, project: project)
        workflow.workflows_workloads.create!(workload: workload, project: project)
        workflow.update!(status: status_enum(:input_required))

        expect_disallowed(:resume_duo_workflow)
      end

      context 'when an eligible Guest invoked the session' do
        let(:current_user) { guest }

        it { expect_allowed(:read_duo_workflow, :update_duo_workflow) }
      end

      context 'when an eligible Guest did not invoke the session' do
        subject(:policy) { described_class.new(guest, workflow) }

        before do
          allow(guest).to receive(:allowed_to_use_for_resource?).and_return(true)
        end

        it { expect_disallowed(:read_duo_workflow, :update_duo_workflow) }
      end

      it 'does not allow access to an unclassified session', :aggregate_failures do
        workflow.update!(execution_mode: nil)

        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:update_duo_workflow)
      end

      context 'when a composite identity service account asks for the local exception' do
        let_it_be(:service_account) do
          create(:user, :service_account, reporter_of: project, composite_identity_enforced: true)
        end

        subject(:policy) { described_class.new(service_account, workflow) }

        before do
          allow(service_account).to receive(:allowed_to_use_for_resource?).and_return(true)
        end

        it { expect_disallowed(:read_duo_workflow, :update_duo_workflow) }
      end
    end
  end

  describe "read_duo_workflow and update_duo_workflow for project-level agentic chat" do
    let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, :agentic_chat, project: project) }

    before do
      allow(policy).to receive(:can?).and_call_original
      allow(policy).to receive(:can?).with(:access_duo_agentic_chat, project).and_return(can_use_agentic_chat)
      allow(policy).to receive(:can?).with(:duo_workflow, project).and_return(true)
    end

    context "when agentic chat is allowed" do
      let(:can_use_agentic_chat) { true }

      context "when current user is workflow owner" do
        before do
          workflow.update!(user: current_user)
        end

        it 'allows read and update workflow policy' do
          expect_allowed(:read_duo_workflow)
          expect_allowed(:update_duo_workflow)
        end

        it { expect_disallowed(:resume_duo_workflow) }

        context 'when workflow is in input_required state' do
          before do
            workflow.update!(status: status_enum(:input_required))
          end

          it { expect_disallowed(:resume_duo_workflow) }
        end
      end

      context "when current user is not workflow owner" do
        before do
          workflow.update!(user: create(:user))
        end

        it 'disallows read, update and resume workflow policy' do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
          expect_disallowed(:resume_duo_workflow)
        end
      end
    end

    context "when agentic chat is disallowed" do
      let(:can_use_agentic_chat) { false }

      before do
        workflow.update!(user: current_user)
      end

      it 'disallows read and update workflow policy' do
        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:update_duo_workflow)
      end
    end
  end

  describe "resume_duo_workflow for a foundational chat agent running in CI" do
    let_it_be_with_reload(:workflow) do
      create(:duo_workflows_workflow, project: project, user: developer,
        workflow_definition: 'analytics_agent/v1')
    end

    let(:agent_enabled) { true }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(true)
      allow(current_user).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true,
        duo_foundational_agents_container: group)
      allow(group).to receive(:foundational_agent_enabled?).and_return(agent_enabled)
      project.project_setting.update!(duo_features_enabled: true)
      workflow.update!(status: status_enum(:input_required))
    end

    context 'when its workload pipeline has finished' do
      before do
        pipeline = create(:ci_pipeline, :success, project: project)
        workload = create(:ci_workload, pipeline: pipeline, project: project)
        workflow.workflows_workloads.create!(workload: workload, project: project)
      end

      it { expect_allowed(:resume_duo_workflow) }

      context 'when the user is not the owner' do
        let(:current_user) { maintainer }

        it { expect_disallowed(:resume_duo_workflow) }
      end

      context 'when the project no longer runs flows in CI' do
        before do
          project.update!(duo_remote_flows_enabled: false)
        end

        it { expect_disallowed(:resume_duo_workflow) }
      end

      context 'when the agent has been turned off for the namespace' do
        let(:agent_enabled) { false }

        it { expect_disallowed(:resume_duo_workflow, :execute_duo_workflow_in_ci) }
      end

      context 'when the namespace has no foundational agent settings' do
        before do
          allow(current_user).to receive(:duo_foundational_agents_container).and_return(nil)
        end

        it { expect_disallowed(:resume_duo_workflow, :execute_duo_workflow_in_ci) }
      end

      context 'when the agent needs Ultimate and the namespace does not have it' do
        before do
          workflow.update!(workflow_definition: 'security_analyst_agent/v1')
          allow(group).to receive(:licensed_feature_available?).and_call_original
          allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(false)
          allow(project).to receive(:root_ancestor).and_return(group)
        end

        it { expect_disallowed(:resume_duo_workflow, :execute_duo_workflow_in_ci) }
      end
    end

    context 'when it never ran in CI' do
      it { expect_disallowed(:resume_duo_workflow) }
    end

    it 'does not treat a session of another kind as a foundational agent' do
      workflow.update!(workflow_definition: 'software_development')

      expect(policy.condition(:foundational_agent_available).pass?).to be(false)
    end
  end

  describe "read_duo_workflow and update_duo_workflow for namespace-level agentic chat" do
    let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, :agentic_chat, namespace: group) }

    before do
      allow(policy).to receive(:can?).and_call_original
      allow(policy).to receive(:can?).with(:access_duo_agentic_chat, group).and_return(can_use_agentic_chat)
      # Namespace-level workflows have no project, so can_use_duo_workflows_in_project is always false
      allow(policy).to receive(:can?).with(:duo_workflow, nil).and_return(false)
    end

    context "when agentic chat is allowed" do
      let(:can_use_agentic_chat) { true }

      context "when current user is workflow owner" do
        before do
          workflow.update!(user: current_user)
        end

        it 'allows read and update workflow policy' do
          expect_allowed(:read_duo_workflow)
          expect_allowed(:update_duo_workflow)
        end

        it { expect_disallowed(:resume_duo_workflow) }

        context 'when workflow is in input_required state' do
          before do
            workflow.update!(status: status_enum(:input_required))
          end

          it { expect_disallowed(:resume_duo_workflow) }
        end
      end

      context "when current user is not workflow owner" do
        before do
          workflow.update!(user: create(:user))
        end

        it 'disallows read, update and resume workflow policy' do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
          expect_disallowed(:resume_duo_workflow)
        end
      end
    end

    context "when agentic chat is disallowed" do
      let(:can_use_agentic_chat) { false }

      before do
        workflow.update!(user: current_user)
      end

      it 'disallows read and update workflow policy' do
        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:update_duo_workflow)
      end
    end
  end

  describe 'resume_duo_workflow' do
    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(current_user).to receive(:allowed_to_use?).and_return(true)
      project.project_setting.update!(duo_features_enabled: true)
      workflow.update!(user: current_user)
    end

    context 'when workflow is not in input_required state' do
      it { expect_disallowed(:resume_duo_workflow) }
    end

    context 'when workflow is in input_required state' do
      before do
        workflow.update!(status: status_enum(:input_required))
      end

      context 'when there are no workloads' do
        it { expect_disallowed(:resume_duo_workflow) }
      end

      context 'when last workload pipeline has a non-completed status' do
        before do
          pipeline = create(:ci_pipeline, project: project)
          workload = create(:ci_workload, pipeline: pipeline, project: project)
          workflow.workflows_workloads.create!(workload: workload, project: project)
        end

        it { expect_disallowed(:resume_duo_workflow) }
      end

      context 'when last workload pipeline has a completed status' do
        before do
          pipeline = create(:ci_pipeline, :success, project: project)
          workload = create(:ci_workload, pipeline: pipeline, project: project)
          workflow.workflows_workloads.create!(workload: workload, project: project)
        end

        it { expect_allowed(:resume_duo_workflow) }

        context 'when user is not the workflow owner' do
          before do
            workflow.update!(user: maintainer)
          end

          it { expect_disallowed(:resume_duo_workflow) }
        end

        context 'when duo workflows are not available for the project' do
          before do
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(false)
          end

          it { expect_disallowed(:resume_duo_workflow) }
        end
      end
    end

    %i[plan_approval_required tool_call_approval_required].each do |status|
      context "when workflow is in #{status} state with a completed workload pipeline" do
        before do
          workflow.update!(status: status_enum(status))
          pipeline = create(:ci_pipeline, :success, project: project)
          workload = create(:ci_workload, pipeline: pipeline, project: project)
          workflow.workflows_workloads.create!(workload: workload, project: project)
        end

        it { expect_allowed(:resume_duo_workflow) }
      end
    end
  end

  describe 'restart_duo_workflow' do
    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(current_user).to receive(:allowed_to_use?).and_return(true)
      project.project_setting.update!(duo_features_enabled: true)
      workflow.update!(user: current_user)
    end

    context 'when workflow is running' do
      before do
        workflow.update!(status: status_enum(:running))
      end

      it { expect_disallowed(:restart_duo_workflow) }
    end

    context 'when workflow is finished' do
      before do
        workflow.update!(status: status_enum(:finished))
      end

      it { expect_disallowed(:restart_duo_workflow) }
    end

    %i[failed stopped].each do |status|
      context "when workflow is #{status}" do
        before do
          workflow.update!(status: status_enum(status))
        end

        it { expect_allowed(:restart_duo_workflow) }

        context 'when user is not the workflow owner' do
          before do
            workflow.update!(user: maintainer)
          end

          it { expect_disallowed(:restart_duo_workflow) }
        end

        context 'when duo workflows are not available for the project' do
          before do
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(false)
          end

          it { expect_disallowed(:restart_duo_workflow) }
        end
      end
    end
  end

  describe "execute_duo_workflow_in_ci" do
    where(:duo_features_enabled, :duo_remote_flows_enabled, :current_user,
      :stage_check, :allowed) do
      true  | false | ref(:developer)  | true  | false
      true  | true  | ref(:developer)  | false | false
      true  | true  | ref(:developer)  | true  | true
      true  | true  | ref(:guest)      | true  | false
      false | true  | ref(:developer)  | true  | false
    end

    with_them do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(stage_check)
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
        project.project_setting.update!(duo_features_enabled: duo_features_enabled,
          duo_remote_flows_enabled: duo_remote_flows_enabled)
        workflow.update!(user: current_user)
      end

      it 'checks execute_duo_workflow_in_ci policy' do
        is_expected.to(allowed ? be_allowed(:execute_duo_workflow_in_ci) : be_disallowed(:execute_duo_workflow_in_ci))
      end
    end
  end

  describe 'delete_duo_workflow' do
    context 'when workflow is a chat workflow' do
      let_it_be(:chat_workflow) { create(:duo_workflows_workflow, :agentic_chat, project: project) }

      let(:workflow) { chat_workflow }

      context 'when user owns the workflow' do
        let(:current_user) { chat_workflow.user }

        it { expect_allowed(:delete_duo_workflow) }
      end

      context 'when user does not own the workflow' do
        let(:current_user) { create(:user) }

        it { expect_disallowed(:delete_duo_workflow) }
      end

      context 'when current user is a service account' do
        let(:current_user) { create(:user, :service_account) }

        context 'when service account does not have composite identity enforced' do
          it { expect_disallowed(:delete_duo_workflow) }
        end

        context 'when service account has composite identity enforced' do
          before do
            current_user.composite_identity_enforced!
          end

          it { expect_allowed(:delete_duo_workflow) }
        end
      end
    end

    context 'when workflow is not a chat workflow' do
      let(:current_user) { workflow.user }

      it { expect_disallowed(:delete_duo_workflow) }
    end
  end

  describe ':read_duo_workflow for compliance reviewers' do
    let_it_be(:reviewer) { create(:user) }
    let(:current_user) { reviewer }

    before_all do
      project.add_owner(reviewer)
    end

    before do
      stub_licensed_features(
        custom_roles: true,
        project_level_compliance_dashboard: true,
        group_level_compliance_dashboard: true
      )
    end

    context 'when workflow is a non-chat workflow' do
      let_it_be(:other_owner) { create(:user) }

      before_all do
        workflow.update!(user: other_owner)
      end

      it { expect_allowed(:read_duo_workflow) }
      it { expect_allowed(:read_agent_artifacts) }
      it { expect_disallowed(:update_duo_workflow) }
    end

    context 'when workflow is a foundational agent workflow' do
      let_it_be(:foundational_workflow) do
        create(:duo_workflows_workflow, project: project,
          workflow_definition: 'security_analyst_agent/v1')
      end

      subject(:policy) { described_class.new(reviewer, foundational_workflow) }

      it { expect_allowed(:read_duo_workflow) }
      it { expect_allowed(:read_agent_artifacts) }
      it { expect_disallowed(:update_duo_workflow) }
    end

    context 'when workflow is a chat session' do
      let_it_be(:chat_workflow) do
        create(:duo_workflows_workflow, :agentic_chat, project: project)
      end

      subject(:policy) { described_class.new(reviewer, chat_workflow) }

      it { expect_disallowed(:read_duo_workflow) }
      it { expect_disallowed(:read_agent_artifacts) }
    end

    context 'when user has :read_agent_artifacts via a project membership only' do
      let_it_be(:project_reviewer) { create(:user) }
      let_it_be(:project_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
      let_it_be(:project_membership) do
        create(:project_member, :guest, member_role: project_role, user: project_reviewer, project: project)
      end

      subject(:policy) { described_class.new(project_reviewer, workflow) }

      it { expect_allowed(:read_agent_artifacts) }
      it { expect_allowed(:read_duo_workflow) }

      it 'does not grant :read_agent_artifacts on the parent group' do
        expect(project_reviewer.can?(:read_agent_artifacts, group)).to be(false)
      end
    end

    context 'when user has no compliance role' do
      let_it_be(:non_compliance_user) { create(:user, developer_of: project) }
      let(:current_user) { non_compliance_user }

      it { expect_disallowed(:read_agent_artifacts) }
      it { expect_disallowed(:read_duo_workflow) }
    end

    context 'when user has :read_agent_artifacts on a different group' do
      let_it_be(:other_reviewer) { create(:user) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:other_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: other_group) }
      let_it_be(:other_membership) do
        create(:group_member, :guest, member_role: other_role, user: other_reviewer, group: other_group)
      end

      subject(:policy) { described_class.new(other_reviewer, workflow) }

      it { expect_disallowed(:read_agent_artifacts) }
      it { expect_disallowed(:read_duo_workflow) }
    end
  end

  describe 'namespace-scoped non-chat sessions' do
    let_it_be_with_reload(:workflow) do
      create(:duo_workflows_workflow, namespace: group, project: nil, environment: :ide)
    end

    let_it_be(:group_developer) { create(:user, developer_of: group) }

    let(:current_user) { group_developer }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :duo_workflow).and_return(true)
      allow(current_user).to receive(:allowed_to_use?).and_return(true)
      workflow.update!(user: current_user)
    end

    it 'lets the owner read and update the session', :aggregate_failures do
      expect_allowed(:read_duo_workflow)
      expect_allowed(:update_duo_workflow)
    end

    context 'when a different group member asks' do
      let_it_be(:other_member) { create(:user, developer_of: group) }

      subject(:policy) { described_class.new(other_member, workflow) }

      it { expect_disallowed(:read_duo_workflow, :update_duo_workflow) }
    end

    it 'keeps remote execution denied, since there is no project to run it in' do
      expect_disallowed(:execute_duo_workflow_in_ci)
    end

    it 'does not let the owner restart a failed session, since there is no project to run it in' do
      workflow.update!(status: status_enum(:failed))

      expect_disallowed(:restart_duo_workflow)
    end

    context 'when a Reporter owns a client-executed session' do
      let_it_be(:reporter) { create(:user, reporter_of: group) }

      let(:current_user) { reporter }

      before do
        workflow.update!(user: current_user, execution_mode: :client)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :agentic_chat).and_return(true)
        allow(current_user).to receive(:allowed_to_use_for_resource?).and_return(true)
      end

      it 'lets the owner read and update the session', :aggregate_failures do
        expect_allowed(:read_duo_workflow)
        expect_allowed(:update_duo_workflow)
      end

      context 'when another eligible group member asks' do
        let_it_be(:other_user) { create(:user, reporter_of: group) }

        subject(:policy) { described_class.new(other_user, workflow) }

        before do
          allow(other_user).to receive(:allowed_to_use_for_resource?).and_return(true)
        end

        it { expect_disallowed(:read_duo_workflow, :update_duo_workflow) }
      end

      it 'does not allow access to a background session', :aggregate_failures do
        workflow.update!(execution_mode: :background)

        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:update_duo_workflow)
      end

      it 'keeps remote execution denied' do
        expect_disallowed(:execute_duo_workflow_in_ci)
      end

      it 'keeps resume denied' do
        expect_disallowed(:resume_duo_workflow)
      end

      context 'when Agentic Chat is unavailable' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :agentic_chat).and_return(false)
        end

        it 'does not allow access to the session', :aggregate_failures do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end
    end
  end

  describe 'private messaging sessions (e.g. Slack)' do
    let_it_be_with_reload(:workflow) do
      create(:duo_workflows_workflow, project: project, environment: :web,
        messaging_callback_context: { 'adapter' => 'slack', 'team_id' => 'T1', 'channel_id' => 'C1' })
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(current_user).to receive(:allowed_to_use?).and_return(true)
      project.project_setting.update!(duo_features_enabled: true)
    end

    context 'when current user is the invoker (workflow owner)' do
      before do
        workflow.update!(user: current_user)
      end

      it 'allows read and update', :aggregate_failures do
        expect_allowed(:read_duo_workflow)
        expect_allowed(:update_duo_workflow)
      end
    end

    context 'when current user is not the invoker' do
      before do
        workflow.update!(user: maintainer)
      end

      it 'disallows read, update, resume and restart even for pipeline-visible environments', :aggregate_failures do
        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:update_duo_workflow)
        expect_disallowed(:resume_duo_workflow)
        expect_disallowed(:restart_duo_workflow)
      end

      context 'when the same workflow has no messaging_callback_context' do
        before do
          workflow.update!(messaging_callback_context: nil)
        end

        it { expect_allowed(:read_duo_workflow) }
      end

      context 'when current user is an admin', :enable_admin_mode do
        let_it_be(:current_user) { create(:admin) }

        it 'disallows read and update even in admin mode', :aggregate_failures do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end

      context 'when the session originates from an in-GitLab note mention (gitlab_duo_note)' do
        before do
          workflow.update!(messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })
        end

        it 'stays readable by project members', :aggregate_failures do
          expect_allowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end
    end

    context 'when current user is a composite-identity service account (executor path)', :request_store do
      let(:current_user) { composite_service_account }

      before do
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
        workflow.update!(user: maintainer)
      end

      context 'when the composite identity is linked to the invoker' do
        before do
          ::Gitlab::Auth::Identity.link_from_scoped_user(current_user, maintainer)
        end

        it 'allows read and update', :aggregate_failures do
          expect_allowed(:read_duo_workflow)
          expect_allowed(:update_duo_workflow)
        end
      end

      context 'when the composite identity is linked to a different user' do
        before do
          ::Gitlab::Auth::Identity.link_from_scoped_user(current_user, developer)
        end

        it 'disallows read and update', :aggregate_failures do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end

      context 'when no composite identity is linked' do
        it 'disallows read and update', :aggregate_failures do
          expect_disallowed(:read_duo_workflow)
          expect_disallowed(:update_duo_workflow)
        end
      end
    end

    context 'when current user is a compliance reviewer with read_agent_artifacts' do
      let_it_be(:reviewer) { create(:user) }
      let(:current_user) { reviewer }

      before_all do
        project.add_owner(reviewer)
        workflow.update!(user: create(:user))
      end

      before do
        stub_licensed_features(
          custom_roles: true,
          project_level_compliance_dashboard: true,
          group_level_compliance_dashboard: true
        )
      end

      it 'disallows read and agent artifacts access', :aggregate_failures do
        expect_disallowed(:read_duo_workflow)
        expect_disallowed(:read_agent_artifacts)
      end
    end
  end

  describe 'autonomous SA as workflow owner' do
    let_it_be(:autonomous_sa) { create(:user, :service_account, developer_of: project) }
    let(:current_user) { autonomous_sa }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(autonomous_sa).to receive(:allowed_to_use?).and_return(true)
      project.project_setting.update!(duo_features_enabled: true)
      workflow.update!(
        user: autonomous_sa,
        trigger_source: :system,
        environment: :web
      )
    end

    it 'recognizes the SA as workflow owner when it is the workflow user' do
      expect_allowed(:read_duo_workflow)
      expect_allowed(:update_duo_workflow)
    end
  end

  describe 'code review flow on an updatable merge request' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
    let_it_be(:code_review_workflow) do
      create(:duo_workflows_workflow, project: project, merge_request_id: merge_request.id,
        workflow_definition: ::Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
    end

    let(:current_user) { developer }

    subject(:policy) { described_class.new(current_user, code_review_workflow) }

    it 'allows a non-owner who can update the merge request to stop the flow, and nothing more' do
      expect_allowed(:stop_duo_workflow)
      expect_disallowed(:update_duo_workflow)
      expect_disallowed(:resume_duo_workflow)
      expect_disallowed(:execute_duo_workflow_in_ci)
    end

    context 'when the workflow has a different workflow_definition' do
      let_it_be(:other_workflow) do
        create(:duo_workflows_workflow, project: project, merge_request_id: merge_request.id,
          workflow_definition: 'software_development')
      end

      subject(:policy) { described_class.new(current_user, other_workflow) }

      it { expect_disallowed(:stop_duo_workflow) }
    end
  end

  describe 'autonomous SA without a Duo seat' do
    let_it_be(:autonomous_sa) do
      create(:user, :service_account, composite_identity_enforced: false,
        provisioned_by_project: project, developer_of: project)
    end

    let(:current_user) { autonomous_sa }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(autonomous_sa).to receive(:allowed_to_use?).and_return(false)
      project.project_setting.update!(duo_features_enabled: true)
      workflow.update!(user: autonomous_sa, trigger_source: :system, environment: :web)
    end

    context 'when it backs an autonomous trigger' do
      before do
        create(:ai_flow_trigger, :for_catalog_consumer, project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_sa)
      end

      it { expect_allowed(:read_duo_workflow) }

      context 'when autonomous_service_account_execution is disabled' do
        before do
          stub_feature_flags(autonomous_service_account_execution: false)
        end

        it { expect_disallowed(:read_duo_workflow) }
      end
    end

    context 'when it backs no trigger' do
      it { expect_disallowed(:read_duo_workflow) }
    end

    context 'when an active trigger points at an account provisioned by another project' do
      let_it_be(:other_project_sa) do
        create(:user, :service_account, composite_identity_enforced: false,
          provisioned_by_project: create(:project), developer_of: project)
      end

      let(:current_user) { other_project_sa }

      before do
        allow(other_project_sa).to receive(:allowed_to_use?).and_return(false)
        workflow.update!(user: other_project_sa, trigger_source: :system, environment: :web)

        create(:ai_flow_trigger, :for_catalog_consumer, project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: other_project_sa)
      end

      it { expect_disallowed(:read_duo_workflow) }
    end

    context 'when an active trigger points at a group-provisioned account' do
      let_it_be(:group_sa) do
        create(:user, :service_account, composite_identity_enforced: false,
          provisioned_by_group: group, developer_of: project)
      end

      let(:current_user) { group_sa }

      before do
        allow(group_sa).to receive(:allowed_to_use?).and_return(false)
        workflow.update!(user: group_sa, trigger_source: :system, environment: :web)

        create(:ai_flow_trigger, :for_catalog_consumer, project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: group_sa)
      end

      it { expect_disallowed(:read_duo_workflow) }
    end

    context 'when an active trigger points at an instance-wide account' do
      let_it_be(:instance_sa) do
        create(:user, :service_account, composite_identity_enforced: false, developer_of: project)
      end

      let(:current_user) { instance_sa }

      before do
        allow(instance_sa).to receive(:allowed_to_use?).and_return(false)
        workflow.update!(user: instance_sa, trigger_source: :system, environment: :web)

        create(:ai_flow_trigger, :for_catalog_consumer, project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: instance_sa)
      end

      it { expect_disallowed(:read_duo_workflow) }
    end

    # Triggers are project-scoped, and projects and namespaces number from
    # separate sequences, so a group id can equal an unrelated project id.
    context 'when a group id collides with the project the trigger belongs to' do
      let_it_be_with_reload(:other_group) { create(:group) }

      before_all do
        other_group.add_owner(autonomous_sa)
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(other_group, :duo_workflow).and_return(true)
        other_group.namespace_settings.update!(duo_features_enabled: true)

        trigger = create(:ai_flow_trigger, :for_catalog_consumer, project: project,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]],
          autonomous_service_account: autonomous_sa)
        trigger.update_column(:project_id, other_group.id)
      end

      it 'does not entitle the account on the group' do
        expect(Ability.allowed?(autonomous_sa, :admin_duo_workflow, other_group)).to be(false)
      end
    end
  end

  describe 'is_workflow_owner condition' do
    let(:workflow) { create(:duo_workflows_workflow, project: project, user: maintainer) }

    context 'when user is the workflow invoker' do
      let(:current_user) { maintainer }

      it 'passes' do
        expect(policy.condition(:is_workflow_owner).pass?).to be(true)
      end
    end

    context 'when user is not the workflow invoker' do
      context 'when user is an AI service account' do
        let(:current_user) { create(:user, :service_account, composite_identity_enforced: true) }

        it 'passes' do
          expect(policy.condition(:is_workflow_owner).pass?).to be(true)
        end
      end

      context 'when user is a regular service account' do
        let(:current_user) { create(:user, :service_account) }

        it 'does not pass' do
          expect(policy.condition(:is_workflow_owner).pass?).to be(false)
        end
      end

      context 'when user is a regular user' do
        let(:current_user) { developer }

        it 'does not pass' do
          expect(policy.condition(:is_workflow_owner).pass?).to be(false)
        end
      end

      context 'when user is nil' do
        let(:current_user) { nil }

        it 'does not pass' do
          expect(policy.condition(:is_workflow_owner).pass?).to be(false)
        end
      end
    end
  end

  describe 'service_account_acting_for_invoker?' do
    let(:workflow) { create(:duo_workflows_workflow, project: project, user: maintainer) }

    context 'when user is an AI service account', :request_store do
      let(:current_user) { create(:user, :service_account, composite_identity_enforced: true) }

      context 'when linked to the invoker' do
        before do
          ::Gitlab::Auth::Identity.link_from_scoped_user(current_user, maintainer)
        end

        it 'passes' do
          expect(policy.condition(:private_session_invoker).pass?).to be(true)
        end
      end

      context 'when linked to another user' do
        before do
          ::Gitlab::Auth::Identity.link_from_scoped_user(current_user, developer)
        end

        it 'does not pass' do
          expect(policy.condition(:private_session_invoker).pass?).to be(false)
        end
      end

      context 'when not linked' do
        it 'does not pass' do
          expect(policy.condition(:private_session_invoker).pass?).to be(false)
        end
      end
    end

    context 'when user is not an AI service account' do
      context 'when user is a regular service account' do
        let(:current_user) { create(:user, :service_account) }

        it 'does not pass' do
          expect(policy.condition(:private_session_invoker).pass?).to be(false)
        end
      end

      context 'when user is a regular user' do
        let(:current_user) { developer }

        it 'does not pass' do
          expect(policy.condition(:private_session_invoker).pass?).to be(false)
        end
      end

      context 'when user is nil' do
        let(:current_user) { nil }

        it 'does not pass' do
          expect(policy.condition(:private_session_invoker).pass?).to be(false)
        end
      end
    end
  end

  def status_enum(status)
    Ai::DuoWorkflows::Workflow.state_machines[:status].states[status].value
  end
end
