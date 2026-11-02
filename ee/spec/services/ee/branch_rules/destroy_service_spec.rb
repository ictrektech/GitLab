# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BranchRules::DestroyService, feature_category: :source_code_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  describe '#execute' do
    subject(:execute) { described_class.new(branch_rule, user: user).execute }

    context 'when branch_rule is a Projects::AllBranchesRule' do
      let(:branch_rule) { Projects::AllBranchesRule.new(project) }

      let_it_be(:approval_project_rules) { create_list(:approval_project_rule, 2, project: project) }
      let_it_be(:external_status_checks) { create_list(:external_status_check, 2, project: project) }

      it 'deletes the approval rules and external status checks' do
        expect { execute }
          .to change { ApprovalProjectRule.count }.by(-2)
          .and change { MergeRequests::ExternalStatusCheck.count }.by(-2)
      end

      it 'returns a success response' do
        expect(execute).to be_success
      end

      context 'if approval rule deletion fails' do
        let(:destroy_service) { ApprovalRules::ProjectRuleDestroyService }
        let(:destroy_service_instance) { instance_double(destroy_service) }
        let(:destroy_service_error) { ServiceResponse.error(message: 'error') }

        before do
          allow(destroy_service).to receive(:new).and_return(destroy_service_instance)
          allow(destroy_service_instance).to receive(:execute).and_return(destroy_service_error)
        end

        it 'returns an error response' do
          response = execute
          expect(response).to be_error
          expect(response[:message]).to eq('Failed to delete approval rules.')
        end
      end

      context 'if external status check deletion fails' do
        let(:destroy_service) { ExternalStatusChecks::DestroyService }
        let(:destroy_service_instance) { instance_double(destroy_service) }
        let(:destroy_service_error) { ServiceResponse.error(message: 'error') }

        before do
          allow(destroy_service).to receive(:new).and_return(destroy_service_instance)
          allow(destroy_service_instance).to receive(:execute).and_return(destroy_service_error)
        end

        it 'returns an error response' do
          response = execute
          expect(response).to be_error
          expect(response[:message]).to eq('Failed to delete external status checks.')
        end
      end
    end

    context 'when branch_rule is a Projects::AllProtectedBranchesRule' do
      let(:branch_rule) { Projects::AllProtectedBranchesRule.new(project) }

      let_it_be(:approval_project_rules) do
        create_list(:approval_project_rule, 2, :for_all_protected_branches, project: project)
      end

      it 'deletes the approval rules' do
        expect { execute }.to change { ApprovalProjectRule.count }.by(-2)
      end

      it 'returns a success response' do
        expect(execute).to be_success
      end

      context 'if approval rule deletion fails' do
        let(:destroy_service) { ApprovalRules::ProjectRuleDestroyService }
        let(:destroy_service_instance) { instance_double(destroy_service) }
        let(:destroy_service_error) { ServiceResponse.error(message: 'error') }

        before do
          allow(destroy_service).to receive(:new).and_return(destroy_service_instance)
          allow(destroy_service_instance).to receive(:execute).and_return(destroy_service_error)
        end

        it 'returns an error response' do
          response = execute
          expect(response).to be_error
          expect(response[:message]).to eq('Failed to delete approval rules.')
        end
      end
    end

    context 'with custom roles' do
      let_it_be(:group, freeze: false) { create(:group) }
      let_it_be(:project, freeze: false) { create(:project, group: group) }
      let_it_be(:user, freeze: false) { create(:user) }
      let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }
      let_it_be_with_reload(:protected_branch) { create(:protected_branch, project: project) }
      let_it_be(:approval_project_rule) do
        create(:approval_project_rule, project: project, protected_branches: [protected_branch])
      end

      before do
        stub_licensed_features(custom_roles: true)
      end

      context 'with admin_protected_branch' do
        before_all do
          create(:member_role, :guest, admin_protected_branch: true, namespace: group, members: [project_member])
        end

        context 'when branch_rule is a Projects::BranchRule' do
          let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }

          it 'deletes the protected branch but keeps its approval rules, matching legacy' do
            expect(execute).to be_success
            expect(protected_branch).to be_destroyed
            expect(approval_project_rule.reload.protected_branches).to be_empty
          end
        end

        context 'when branch_rule is a Projects::AllBranchesRule' do
          let(:branch_rule) { Projects::AllBranchesRule.new(project) }

          it 'returns an access denied error' do
            expect(execute.reason).to eq(:access_denied)
          end
        end

        context 'when branch_rule is a Projects::AllProtectedBranchesRule' do
          let(:branch_rule) { Projects::AllProtectedBranchesRule.new(project) }

          it 'returns an access denied error' do
            expect(execute.reason).to eq(:access_denied)
          end
        end
      end

      context 'with manage_merge_request_settings' do
        before_all do
          create(:member_role, :guest, :manage_merge_request_settings, namespace: group, members: [project_member])
        end

        context 'when branch_rule is a Projects::BranchRule' do
          let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }

          it 'returns an access denied error' do
            expect(execute.reason).to eq(:access_denied)
            expect(ProtectedBranch.exists?(protected_branch.id)).to be(true)
          end
        end

        context 'when branch_rule is a Projects::AllBranchesRule' do
          let(:branch_rule) { Projects::AllBranchesRule.new(project) }

          let!(:all_branches_approval_rule) { create(:approval_project_rule, project: project) }
          let!(:external_status_check) { create(:external_status_check, project: project) }

          it 'deletes the approval rules and external status checks' do
            expect(execute).to be_success
            expect { all_branches_approval_rule.reload }.to raise_error(ActiveRecord::RecordNotFound)
            expect { external_status_check.reload }.to raise_error(ActiveRecord::RecordNotFound)
            expect(approval_project_rule.reload).to be_persisted
          end
        end

        context 'when branch_rule is a Projects::AllProtectedBranchesRule' do
          let(:branch_rule) { Projects::AllProtectedBranchesRule.new(project) }

          let!(:all_protected_approval_rule) do
            create(:approval_project_rule, :for_all_protected_branches, project: project)
          end

          it 'deletes the approval rules' do
            expect(execute).to be_success
            expect { all_protected_approval_rule.reload }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
