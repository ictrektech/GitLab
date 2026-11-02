# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ExecuteMergeRequestRequestedChangesWorkflowTriggersWorker, feature_category: :dap_triggers do
  let_it_be(:user) { create(:user) }
  # In a group, for the catalog consumer of the Duo Developer flow trigger.
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
    )
  end

  let_it_be_with_reload(:reviewer) do
    create(:merge_request_reviewer, merge_request: merge_request, reviewer: user, state: :requested_changes)
  end

  let(:cloud_event) do
    MergeRequests::RequestedChangesCloudEvent.build(merge_request: merge_request, current_user: user)
  end

  let(:resource) { merge_request }
  let(:event) { cloud_event }

  let(:wrong_event) do
    MergeRequests::ApprovedCloudEvent.build(
      merge_request: merge_request,
      current_user: user,
      approval: instance_double(Approval, created_at: Time.current)
    )
  end

  let(:doomed_resource) do
    create(:merge_request, source_project: project, target_project: project, source_branch: 'doomed-branch')
  end

  let(:doomed_resource_event) do
    MergeRequests::RequestedChangesCloudEvent.build(merge_request: doomed_resource, current_user: user)
  end

  it_behaves_like 'subscribes to event'
  it_behaves_like 'a cloud events flow trigger worker' do
    let(:additional_run_params) { { reviewer_username: user.username } }
  end

  it 'retries lock contention after the lease expires and uses the default backoff for other errors',
    :aggregate_failures do
    retry_in = described_class.sidekiq_retry_in_block

    expect(retry_in.call(1, described_class::LeaseTakenError.new, {})).to eq(described_class::LEASE_TTL.to_i)
    expect(retry_in.call(1, StandardError.new, {})).to be_nil
  end

  describe '#handle_event' do
    subject(:handle_event) { worker.handle_event(cloud_event) }

    let(:worker) { described_class.new }
    let(:run_service) { instance_double(Ai::FlowTriggers::RunService, execute: nil) }
    let(:run_params) do
      {
        input: merge_request.iid.to_s,
        event: :merge_request,
        action: 'requested_changes',
        reviewer_username: cloud_event.current_user.username
      }
    end

    before do
      allow(Ai::FlowTriggers::FilterEvaluator).to receive(:new)
        .and_return(instance_double(Ai::FlowTriggers::FilterEvaluator, allowed?: true))
      allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
      allow(worker.logger).to receive(:info)
    end

    shared_examples 'skips flow triggers and logs' do |message|
      it 'does not start a flow and logs the reason' do
        expect(worker.logger).to receive(:info).with(hash_including('message' => message))
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when dap_software_factory is disabled' do
      before do
        stub_feature_flags(dap_software_factory: false)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when dap_software_factory is enabled for the root namespace of the project' do
      before do
        stub_feature_flags(dap_software_factory: project.root_ancestor)
      end

      it 'starts a flow' do
        expect(run_service).to receive(:execute).with(run_params)

        handle_event
      end
    end

    context 'when dap_software_factory is enabled for the project only' do
      before do
        stub_feature_flags(dap_software_factory: project)
      end

      it 'starts a flow' do
        expect(run_service).to receive(:execute).with(run_params)

        handle_event
      end
    end

    context 'when the reviewer no longer requests changes' do
      before do
        reviewer.update!(state: :reviewed)
      end

      it_behaves_like 'skips flow triggers and logs', 'Reviewer no longer requests changes.'
    end

    context 'when the event user is no longer a reviewer' do
      before do
        reviewer.destroy!
      end

      it_behaves_like 'skips flow triggers and logs', 'Reviewer no longer requests changes.'
    end

    context 'when another job handles a verdict on the merge request', :clean_gitlab_redis_shared_state do
      before do
        Gitlab::ExclusiveLease.new("#{described_class.name.underscore}:#{merge_request.id}", timeout: 1.minute)
          .try_obtain
      end

      it 'does not start a flow and raises an error to retry the job' do
        expect(run_service).not_to receive(:execute)

        expect { handle_event }
          .to raise_error(described_class::LeaseTakenError,
            "Another job holds the lease for merge request #{merge_request.id}.")
      end
    end

    context 'when a flow acting with a composite identity requests changes', :request_store do
      let_it_be(:flow_service_account) { create(:user, :service_account, composite_identity_enforced: true) }
      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

      let(:cloud_event) do
        ::Gitlab::ApplicationContext.with_context(duo_workflow_id: parent_workflow.id.to_s) do
          MergeRequests::RequestedChangesCloudEvent.build(merge_request: merge_request, current_user: user)
        end
      end

      before do
        ::Gitlab::Auth::Identity.fabricate(flow_service_account).link!(user, context: :authentication)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :update_duo_workflow, parent_workflow).and_return(true)
      end

      it 'starts a flow chained from the authorized parent workflow' do
        expect(Ai::FlowTriggers::RunService).to receive(:new)
          .with(hash_including(current_user: user, parent_workflow: parent_workflow))
          .and_return(run_service)
        expect(run_service).to receive(:execute).with(run_params)

        handle_event
      end

      context 'when ai_flow_trigger_chaining is disabled' do
        before do
          stub_feature_flags(ai_flow_trigger_chaining: false)
        end

        it 'does not start a flow and logs the composite actor' do
          expect(worker.logger).to receive(:info).with(hash_including(
            'message' => 'Event caused by a flow, skipping flow triggers.',
            'gitlab_composite_actor_id' => flow_service_account.id
          ))
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end
    end

    context 'with a Duo Code Review verdict' do
      let_it_be(:review_bot) { create(:user, :duo_code_review_bot) }
      let_it_be(:code_review_definition) { Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference }
      let_it_be(:review_workflow) do
        create(:duo_workflows_workflow,
          project: project,
          merge_request: merge_request,
          user: user,
          workflow_definition: code_review_definition)
      end

      let(:review_workflow_id) { review_workflow.id }
      let(:cloud_event) do
        MergeRequests::RequestedChangesCloudEvent.build(
          merge_request: merge_request,
          current_user: review_bot,
          review_workflow_id: review_workflow_id
        )
      end

      before_all do
        create(:merge_request_reviewer, merge_request: merge_request, reviewer: review_bot, state: :requested_changes)
      end

      it 'starts a flow chained from the review workflow', :aggregate_failures do
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          project: project,
          current_user: review_bot,
          flow_trigger: flow_trigger,
          resource: merge_request,
          parent_workflow: review_workflow
        ).and_return(run_service)
        expect(run_service).to receive(:execute).with(run_params)

        handle_event
      end

      context 'when the review bot no longer requests changes' do
        before do
          merge_request.find_reviewer(review_bot).update!(state: :reviewed)
        end

        it_behaves_like 'skips flow triggers and logs', 'Reviewer no longer requests changes.'
      end

      context 'when ai_flow_trigger_chaining is disabled' do
        before do
          stub_feature_flags(ai_flow_trigger_chaining: false)
        end

        it_behaves_like 'skips flow triggers and logs', 'Event caused by a flow, skipping flow triggers.'
      end

      shared_examples 'skips flow triggers without a trusted review workflow' do
        it 'does not start a flow and logs the review workflow' do
          expect(worker.logger).to receive(:info).with(hash_including(
            'message' => 'Event caused by a flow without an authorized parent workflow, skipping flow triggers.',
            Labkit::Fields::DUO_WORKFLOW_ID => review_workflow_id
          ))
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end

      context 'when the event has no review workflow' do
        let(:review_workflow_id) { nil }

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the review workflow does not exist' do
        let(:review_workflow_id) { non_existing_record_id }

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the review workflow belongs to another project' do
        let(:review_workflow_id) do
          create(:duo_workflows_workflow, merge_request: merge_request, workflow_definition: code_review_definition).id
        end

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when a user other than the review bot publishes the review workflow' do
        let(:cloud_event) do
          MergeRequests::RequestedChangesCloudEvent.build(
            merge_request: merge_request,
            current_user: user,
            review_workflow_id: review_workflow_id
          )
        end

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the review workflow reviews another merge request' do
        let(:review_workflow_id) do
          other_merge_request = create(:merge_request, source_project: project, target_project: project,
            source_branch: 'other-branch')

          create(:duo_workflows_workflow,
            project: project, merge_request: other_merge_request, workflow_definition: code_review_definition).id
        end

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the workflow is not a code review session' do
        let(:review_workflow_id) do
          create(:duo_workflows_workflow,
            project: project,
            merge_request: merge_request,
            workflow_definition: Ai::Catalog::FoundationalFlow.developer_v1.reference).id
        end

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the workflow is a Duo conversation on the merge request' do
        let(:review_workflow_id) do
          create(:duo_workflows_workflow,
            project: project,
            merge_request: merge_request,
            workflow_definition: code_review_definition,
            messaging_callback_context: { 'adapter' => Ai::Messaging::Adapters::GitlabDuoNote.adapter_key }).id
        end

        it_behaves_like 'skips flow triggers without a trusted review workflow'
      end

      context 'when the flow trigger already ran for the review workflow' do
        let(:trigger_event_type) { :merge_request }

        before do
          create(:duo_workflows_workflow,
            project: project,
            trigger_source: :flow,
            parent_workflow: review_workflow,
            trigger_flow_trigger: flow_trigger,
            trigger_event_type: trigger_event_type,
            service_account: service_account)
        end

        it_behaves_like 'skips flow triggers and logs', 'Flow trigger already ran for this review verdict.'

        it 'checks the earlier runs on the primary' do
          lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(review_workflow.load_balancer)
          allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_return(lb_session)
          expect(lb_session).to receive(:use_primary).and_call_original

          handle_event
        end

        context 'when the run of the flow trigger is for a mention' do
          let(:trigger_event_type) { :mention }

          it 'starts a flow' do
            expect(run_service).to receive(:execute).with(run_params)

            handle_event
          end
        end

        context 'when another flow trigger has not run for the review workflow' do
          let_it_be(:other_service_account) { create(:service_account) }
          let_it_be(:other_flow_trigger) do
            create(:ai_flow_trigger,
              project: project,
              user: other_service_account,
              event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
            )
          end

          it 'starts only the flow of the other flow trigger', :aggregate_failures do
            expect(Ai::FlowTriggers::RunService).to receive(:new)
              .with(hash_including(flow_trigger: other_flow_trigger, parent_workflow: review_workflow))
              .and_return(run_service)
            expect(Ai::FlowTriggers::RunService).not_to receive(:new).with(hash_including(flow_trigger: flow_trigger))
            expect(run_service).to receive(:execute).once

            handle_event
          end
        end
      end

      context 'when another job handles the same verdict', :clean_gitlab_redis_shared_state do
        before do
          Gitlab::ExclusiveLease.new("#{described_class.name.underscore}:#{merge_request.id}", timeout: 1.minute)
            .try_obtain
        end

        it 'does not start a flow and raises an error to retry the job' do
          expect(run_service).not_to receive(:execute)

          expect { handle_event }
            .to raise_error(described_class::LeaseTakenError,
              "Another job holds the lease for merge request #{merge_request.id}.")
        end
      end
    end

    context 'with a Duo Developer flow trigger' do
      let_it_be(:developer_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
      end

      let_it_be(:developer_trigger) do
        create(:ai_flow_trigger, :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
            project: project, item: developer_item),
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
        )
      end

      let(:developer_run_service) { instance_double(Ai::FlowTriggers::RunService, execute: run_response) }
      let(:run_response) { ServiceResponse.success }
      let(:check_result) { ServiceResponse.success }
      let(:config) { Ai::FlowTriggers::FixLoop::Config.new(nil) }
      let(:stop_service) { instance_double(Ai::FlowTriggers::FixLoop::StopService, execute: ServiceResponse.success) }

      before do
        allow(Ai::FlowTriggers::RunService).to receive(:new)
          .with(hash_including(flow_trigger: developer_trigger)).and_return(developer_run_service)
        allow(Ai::FlowTriggers::FixLoop::Check).to receive(:new)
          .with(merge_request, reviewer: user, verdict_at: Time.iso8601(cloud_event.data[:time]))
          .and_return(instance_double(Ai::FlowTriggers::FixLoop::Check, execute: check_result))
        allow(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).and_return(stop_service)
      end

      def expect_stop(reason, details)
        expect(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).with(merge_request,
          service_account: developer_trigger.service_account, reason: reason, details: details
        ).and_return(stop_service)
        expect(stop_service).to receive(:execute)
      end

      it 'starts the fix run, and the other flow without the checks of the fix loop', :aggregate_failures do
        expect(developer_run_service).to receive(:execute).with(run_params)
        expect(run_service).to receive(:execute).with(run_params)
        expect(Ai::FlowTriggers::FixLoop::StopService).not_to receive(:new)

        handle_event
      end

      context 'when the check of the fix loop starts no fix run' do
        let(:check_result) do
          ServiceResponse.error(message: 'Merge request is a draft.', reason: :draft, payload: {})
        end

        it 'does not start the fix run and logs the reason', :aggregate_failures do
          expect(worker.logger).to receive(:info).with(hash_including(
            'message' => 'Merge request is a draft.',
            'reason' => :draft,
            'flow_trigger_id' => developer_trigger.id,
            'merge_request_id' => merge_request.id
          ))
          expect(developer_run_service).not_to receive(:execute)
          expect(run_service).to receive(:execute).with(run_params)
          expect(Ai::FlowTriggers::FixLoop::StopService).not_to receive(:new)

          handle_event
        end
      end

      context 'when the loop reached max_fix_runs' do
        let(:check_result) do
          ServiceResponse.error(message: 'Fix loop reached max_fix_runs.', reason: :max_fix_runs,
            payload: { config: config, fix_runs: 3 })
        end

        it 'stops the fix loop instead of starting a fix run', :aggregate_failures do
          expect_stop(:max_fix_runs, { reviewer: user, max_fix_runs: 3 })
          expect(developer_run_service).not_to receive(:execute)

          handle_event
        end
      end

      context 'when the configuration is not valid' do
        let(:config) { Ai::FlowTriggers::FixLoop::Config.new("review:\n  max_rounds: 3\n") }
        let(:check_result) do
          ServiceResponse.error(message: 'Review configuration is not valid.', reason: :invalid_config,
            payload: { config: config })
        end

        it 'tells the author instead of starting a fix run', :aggregate_failures do
          expect_stop(:invalid_config, { errors: ['Unknown keys: `max_rounds`.'] })
          expect(developer_run_service).not_to receive(:execute)

          handle_event
        end
      end

      context 'when the fix run does not start' do
        let(:run_response) { ServiceResponse.error(message: 'workflow chain is too deep') }

        it 'stops the fix loop' do
          expect_stop(:fix_run_not_started, {})

          handle_event
        end
      end

      context 'when the check of the fix loop raises an error' do
        before do
          allow(Ai::FlowTriggers::FixLoop::Check).to receive(:new).and_raise(StandardError, 'Gitaly is not available')
        end

        it 'tracks the error and stops the fix loop', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(StandardError), hash_including(flow_trigger_id: developer_trigger.id))
          expect_stop(:fix_run_not_started, {})
          expect(developer_run_service).not_to receive(:execute)

          handle_event
        end
      end

      context 'when the fix run raises an error' do
        before do
          allow(developer_run_service).to receive(:execute).and_raise(StandardError, 'Gitaly is not available')
        end

        it 'tracks the error and stops the fix loop', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(StandardError), hash_including(flow_trigger_id: developer_trigger.id))
          expect_stop(:fix_run_not_started, {})

          handle_event
        end
      end

      context 'when the flow trigger is inherited from the top-level group' do
        # The group already enables developer_item for the project trigger.
        let_it_be(:inherited_developer_item) do
          create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
        end

        let_it_be(:inheritance_consumer) do
          create(:ai_catalog_item_consumer, :inheritance, group: project.root_ancestor, item: inherited_developer_item)
        end

        let_it_be(:inherited_trigger) do
          create(:ai_flow_trigger, :for_inheritance_consumer,
            group: project.root_ancestor,
            ai_catalog_item_consumer: inheritance_consumer,
            event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
          )
        end

        let(:config) { Ai::FlowTriggers::FixLoop::Config.new("review:\n  max_rounds: 3\n") }
        let(:check_result) do
          ServiceResponse.error(message: 'Review configuration is not valid.', reason: :invalid_config,
            payload: { config: config })
        end

        it 'adds its service account to the project before it tells the author' do
          service_account = inheritance_consumer.service_account

          expect(Ai::FlowTriggers::FixLoop::StopService).to receive(:new)
            .with(merge_request, hash_including(service_account: service_account)) do
              expect(project.member(service_account)).to be_present

              stop_service
            end

          handle_event
        end

        context 'when the service account does not join the project' do
          before do
            allow_next_instance_of(Ai::Catalog::AddServiceAccountToProjectService) do |service|
              allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Lock not obtained'))
            end
          end

          it 'logs the error and still stops the fix loop', :aggregate_failures do
            expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(
              message: 'Fix loop could not add the service account to the project.',
              flow_trigger_id: inherited_trigger.id,
              error_message: 'Lock not obtained'
            ))
            expect(Ai::FlowTriggers::FixLoop::StopService).to receive(:new)
              .with(merge_request, hash_including(service_account: inheritance_consumer.service_account))
              .and_return(stop_service)

            handle_event
          end
        end

        context 'when the inherited flow trigger has no service account' do
          before do
            Ai::Catalog::ItemConsumer.id_in(inheritance_consumer.id).update_all(service_account_id: nil)
          end

          it 'does not add a service account to the project', :aggregate_failures do
            expect(Ai::Catalog::AddServiceAccountToProjectService).not_to receive(:new)
            expect(Ai::FlowTriggers::FixLoop::StopService).to receive(:new)
              .with(merge_request, hash_including(service_account: nil)).and_return(stop_service)

            handle_event
          end
        end
      end

      context 'when the run of the other flow does not start' do
        before do
          allow(run_service).to receive(:execute).and_return(ServiceResponse.error(message: 'not started'))
        end

        it 'does not stop the fix loop' do
          expect(Ai::FlowTriggers::FixLoop::StopService).not_to receive(:new)

          handle_event
        end
      end

      context 'with the checks of the fix loop', :aggregate_failures do
        let_it_be_with_reload(:loop_merge_request) do
          create(:merge_request, source_project: project, target_project: project, source_branch: 'loop-branch')
        end

        let(:cloud_event) do
          MergeRequests::RequestedChangesCloudEvent.build(merge_request: loop_merge_request, current_user: user)
        end

        before_all do
          project.add_developer(developer_trigger.service_account)
          create(:merge_request_reviewer, merge_request: loop_merge_request, reviewer: user, state: :requested_changes)
          create(:duo_workflows_workflow_merge_request,
            workflow: create(:duo_workflows_workflow, project: project),
            merge_request: loop_merge_request, project: project, link_type: :created)
          # Before the verdict, so they do not answer it.
          travel_to(1.hour.ago) do
            create_list(:duo_workflows_workflow, 3, :finished,
              project: project,
              merge_request: loop_merge_request,
              workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
              trigger_event_type: :merge_request)
          end
        end

        before do
          allow(Ai::FlowTriggers::FixLoop::Check).to receive(:new).and_call_original
          allow(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).and_call_original
          allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project)
            .and_return(Ai::FlowTriggers::FixLoop::Config.new("review:\n  reviewer: #{user.username}\n"))
        end

        it 'marks the merge request as a draft at max_fix_runs and tells the author' do
          expect(developer_run_service).not_to receive(:execute)

          handle_event

          expect(loop_merge_request.reload).to be_draft
          expect(loop_merge_request.notes.user.authored_by(developer_trigger.service_account).sole.note)
            .to include("@#{loop_merge_request.author.username} `#{user.username}` requested changes after 3 fix runs")
        end

        context 'with two events for one Duo Code Review verdict' do
          let_it_be(:review_bot) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
          let_it_be(:review_workflow) do
            create(:duo_workflows_workflow,
              project: project,
              merge_request: loop_merge_request,
              user: user,
              workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
          end

          let(:cloud_event) do
            MergeRequests::RequestedChangesCloudEvent.build(
              merge_request: loop_merge_request, current_user: review_bot, review_workflow_id: review_workflow.id
            )
          end

          before_all do
            create(:merge_request_reviewer,
              merge_request: loop_merge_request, reviewer: review_bot, state: :requested_changes)
          end

          before do
            allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project)
              .and_return(Ai::FlowTriggers::FixLoop::Config.new(nil))
          end

          it 'stops the loop once' do
            expect(developer_run_service).not_to receive(:execute)

            2.times { described_class.new.handle_event(cloud_event) }

            expect(loop_merge_request.reload).to be_draft
            expect(loop_merge_request.notes.user.authored_by(developer_trigger.service_account).count).to eq(1)
          end
        end
      end
    end
  end
end
