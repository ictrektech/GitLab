# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::TrackClosedMrWorker,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  # Provisioned by the project, not merely a member: that is how the bot resolves.
  let_it_be(:dep_mgmt_sa) do
    create(:user, :service_account,
      name: DependencyManagement::ProvisionServiceAccountService::SERVICE_ACCOUNT_NAME,
      provisioned_by_project: project)
  end

  let_it_be(:component) { create(:sbom_component, :bundler) }
  let_it_be(:sbom_occurrence) { create(:sbom_occurrence, project: project, component: component) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
  let_it_be(:merge_request) do
    create(:merge_request, :closed,
      source_project: project,
      target_project: project,
      author: dep_mgmt_sa,
      source_branch: 'dependency-management/rack-3.x')
  end

  let(:event) do
    MergeRequests::ClosedEvent.new(data: {
      merge_request_id: merge_request.id,
      source: MergeRequests::ClosedEvent::SOURCE_TYPES[:dependency_management_auto_remediation]
    })
  end

  subject(:handle_event) { described_class.new.handle_event(event) }

  before_all do
    create(:sbom_occurrences_vulnerability, occurrence: sbom_occurrence, vulnerability: vulnerability)
    create(:vulnerabilities_merge_request_link, merge_request: merge_request, vulnerability: vulnerability)
  end

  it_behaves_like 'subscribes to event'

  describe '#handle_event' do
    context 'when the merge_request has a linked vulnerability with an sbom_occurrence' do
      it 'tracks the close event with purl_type and merge_request_id' do
        expect { handle_event }
          .to trigger_internal_events('close_dependency_management_auto_remediation_mr')
          .with(
            project: project,
            additional_properties: {
              purl_type: 'gem',
              merge_request_id: merge_request.id
            }
          )
      end
    end

    context 'when the linked vulnerability has no sbom_occurrences' do
      let_it_be(:other_vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let_it_be(:other_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          author: dep_mgmt_sa,
          source_branch: 'dependency-management/foo-1.x')
      end

      let(:event) { MergeRequests::ClosedEvent.new(data: { merge_request_id: other_mr.id }) }

      before_all do
        create(:vulnerabilities_merge_request_link,
          merge_request: other_mr, vulnerability: other_vulnerability)
      end

      it 'tracks the close event with a nil purl_type' do
        expect { handle_event }
          .to trigger_internal_events('close_dependency_management_auto_remediation_mr')
          .with(
            project: project,
            additional_properties: {
              purl_type: nil,
              merge_request_id: other_mr.id
            }
          )
      end
    end

    context 'when the merge_request does not exist' do
      let(:event) { MergeRequests::ClosedEvent.new(data: { merge_request_id: non_existing_record_id }) }

      it 'does not track the close event' do
        expect { handle_event }
          .not_to trigger_internal_events('close_dependency_management_auto_remediation_mr')
      end
    end

    describe 'the recorded remediation state' do
      let_it_be(:closer) { create(:user) }
      let_it_be_with_reload(:remediation) do
        create(:dependency_management_remediation, project: project, merge_request: merge_request)
      end

      def close_by(user)
        MergeRequest::Metrics.where(merge_request_id: merge_request.id).update_all(latest_closed_by_id: user&.id)
      end

      # No repository here, so branch existence is asserted rather than created.
      before do
        allow_next_found_instance_of(MergeRequest) do |mr|
          allow(mr).to receive(:source_branch_exists?).and_return(true)
        end
      end

      context 'when someone other than the bot closed it' do
        before do
          close_by(closer)
        end

        it 'records a dismissal' do
          expect { handle_event }.to change { remediation.reload.state }.from('open').to('dismissed')
        end
      end

      context 'when the merge request was reopened before this ran' do
        before do
          close_by(closer)
          MergeRequest.id_in(merge_request.id).update_all(state_id: MergeRequest.available_states[:opened])
        end

        it 'leaves the remediation open' do
          expect { handle_event }.not_to change { remediation.reload.state }.from('open')
        end
      end

      context 'when the close cannot be attributed to anyone' do
        before do
          close_by(nil)
        end

        it 'leaves the remediation open, so the bump is re-proposed' do
          expect { handle_event }.not_to change { remediation.reload.state }.from('open')
        end
      end

      context 'when the bot closed its own merge request' do
        before do
          close_by(dep_mgmt_sa)
        end

        # Nobody declined, so a dismissal here would silence it for good.
        it 'leaves the remediation open, so the bump is re-proposed' do
          expect { handle_event }.not_to change { remediation.reload.state }.from('open')
        end
      end

      context 'when the merge request has no metrics' do
        before do
          merge_request.metrics.destroy!
          merge_request.reload
        end

        it 'leaves the remediation open, so the bump is re-proposed' do
          expect { handle_event }.not_to change { remediation.reload.state }.from('open')
        end
      end

      context 'when the project has no service account' do
        let_it_be(:bare_project) { create(:project) }
        let_it_be(:bare_mr) do
          create(:merge_request, :closed,
            source_project: bare_project,
            target_project: bare_project,
            source_branch: 'dependency-management/rack-3.x')
        end

        let_it_be_with_reload(:bare_remediation) do
          create(:dependency_management_remediation, project: bare_project, merge_request: bare_mr)
        end

        let(:event) do
          MergeRequests::ClosedEvent.new(data: {
            merge_request_id: bare_mr.id,
            source: MergeRequests::ClosedEvent::SOURCE_TYPES[:dependency_management_auto_remediation]
          })
        end

        before do
          bare_mr.metrics.update!(latest_closed_by_id: closer.id)
        end

        it 'records a dismissal, since the closer cannot be the bot' do
          expect { handle_event }.to change { bare_remediation.reload.state }.from('open').to('dismissed')
        end
      end

      context 'when the source branch was deleted' do
        before do
          allow_next_found_instance_of(MergeRequest) do |mr|
            allow(mr).to receive(:source_branch_exists?).and_return(false)
          end

          close_by(closer)
        end

        # Routine cleanup should not read as a decline.
        it 'leaves the remediation open, so the bump is re-proposed' do
          expect { handle_event }.not_to change { remediation.reload.state }.from('open')
        end
      end

      context 'with a remediation belonging to another merge request' do
        let_it_be_with_reload(:other_remediation) do
          create(:dependency_management_remediation,
            project: project, package_name: 'other', merge_request: nil)
        end

        before do
          close_by(closer)
        end

        it 'leaves it alone' do
          expect { handle_event }.not_to change { other_remediation.reload.state }
        end
      end
    end
  end
end
