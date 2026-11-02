# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::TrackReopenedMrWorker,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:dep_mgmt_sa) do
    create(:user, :service_account,
      name: DependencyManagement::ProvisionServiceAccountService::SERVICE_ACCOUNT_NAME,
      provisioned_by_project: project)
  end

  let_it_be(:merge_request) do
    create(:merge_request,
      source_project: project,
      target_project: project,
      author: dep_mgmt_sa,
      source_branch: 'dependency-management/rack-3.x')
  end

  let(:event) { MergeRequests::ReopenedEvent.new(data: { merge_request_id: merge_request.id }) }

  subject(:handle_event) { described_class.new.handle_event(event) }

  it_behaves_like 'subscribes to event'

  describe '#handle_event' do
    let_it_be_with_reload(:remediation) do
      create(:dependency_management_remediation,
        project: project, merge_request: merge_request, state: :dismissed)
    end

    # Otherwise a close nobody meant holds until a higher fix version appears.
    it 'withdraws the dismissal' do
      expect { handle_event }.to change { remediation.reload.state }.from('dismissed').to('open')
    end

    context 'with a merged row for the same merge request' do
      let_it_be_with_reload(:merged_row) do
        create(:dependency_management_remediation,
          project: project, package_name: 'other', merge_request: merge_request, state: :merged)
      end

      it 'leaves it alone' do
        expect { handle_event }.not_to change { merged_row.reload.state }.from('merged')
      end
    end

    context 'with a remediation belonging to another merge request' do
      let_it_be_with_reload(:other_remediation) do
        create(:dependency_management_remediation,
          project: project, package_name: 'elsewhere', merge_request: nil, state: :dismissed)
      end

      it 'leaves it alone' do
        expect { handle_event }.not_to change { other_remediation.reload.state }.from('dismissed')
      end
    end

    context 'when the merge request was closed again before this ran' do
      before do
        MergeRequest.id_in(merge_request.id).update_all(state_id: MergeRequest.available_states[:closed])
      end

      it 'keeps the newer dismissal' do
        expect { handle_event }.not_to change { remediation.reload.state }.from('dismissed')
      end
    end

    context 'when the merge request does not exist' do
      let(:event) { MergeRequests::ReopenedEvent.new(data: { merge_request_id: non_existing_record_id }) }

      it 'does nothing' do
        expect { handle_event }.not_to change { remediation.reload.state }
      end
    end
  end
end
