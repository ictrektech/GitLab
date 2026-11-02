# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::IngestAuditEventsService, feature_category: :audit_events do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }

  let(:event_id_one) { SecureRandom.uuid }
  let(:event_id_two) { SecureRandom.uuid }
  let(:event_time_one) { DateTime.parse('2026-01-01T00:00:00Z') }
  let(:event_time_two) { DateTime.parse('2026-01-01T00:00:01Z') }

  let(:events) do
    [
      {
        id: event_id_one,
        type: 'ai_llm_input_sent',
        source: '/duo_workflow_service',
        time: event_time_one,
        data: { model: 'claude-3' }
      },
      {
        id: event_id_two,
        type: 'ai_llm_response_received',
        source: '/duo_workflow_service',
        time: event_time_two,
        data: {}
      }
    ]
  end

  subject(:service) do
    described_class.new(
      workflow: workflow,
      events: events,
      current_user: user
    )
  end

  describe '#execute' do
    before do
      project.project_setting.update!(ai_audit_events_storage_enabled: true)
    end

    context 'when workflow has no project_id' do
      let_it_be(:group) { create(:group) }
      let_it_be(:namespace_workflow) do
        create(:duo_workflows_workflow, user: user, project: nil, namespace: group)
      end

      before do
        group.reload.namespace_settings.update!(ai_audit_events_storage_enabled: true)
      end

      subject(:service) do
        described_class.new(workflow: namespace_workflow, events: events, current_user: user)
      end

      it 'sets namespace_id and leaves project_id nil' do
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
          .to receive(:perform_async)
          .with(array_including(
            hash_including('project_id' => nil, 'namespace_id' => group.id, 'workflow_id' => namespace_workflow.id)
          ))

        service.execute
      end
    end

    context 'when governance_session_id is not provided' do
      it 'sets workflow_id from the workflow and leaves ai_governance_session_id nil' do
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
          .to receive(:perform_async)
          .with(array_including(
            hash_including('workflow_id' => workflow.id, 'ai_governance_session_id' => nil)
          ))

        service.execute
      end
    end

    context 'when governance_session_id is provided' do
      subject(:service) do
        described_class.new(
          workflow: workflow,
          governance_session_id: 999,
          events: events,
          current_user: user
        )
      end

      it 'sets ai_governance_session_id, project_id, and leaves workflow_id and namespace_id nil' do
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
          .to receive(:perform_async)
          .with(array_including(
            hash_including(
              'workflow_id' => nil,
              'ai_governance_session_id' => 999,
              'project_id' => workflow.project_id,
              'namespace_id' => nil
            )
          ))

        service.execute
      end
    end

    context 'when ingesting events' do
      it 'enqueues ProcessAuditEventsWorker with the built event attributes' do
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
          .to receive(:perform_async)
          .with(array_including(
            hash_including('cloud_event_id' => event_id_one, 'event_name' => 'ai_llm_input_sent'),
            hash_including('cloud_event_id' => event_id_two, 'event_name' => 'ai_llm_response_received')
          ))

        service.execute
      end

      it 'returns success with the event count without waiting for processing' do
        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

        result = service.execute

        expect(result).to be_success
        expect(result.payload).to eq({ status: 'accepted', count: 2 })
      end

      it 'does not perform any storage or logging synchronously when the events are stored' do
        expect(::AuditEvents::AiAuditEvent).not_to receive(:bulk_insert!)
        expect(ClickHouse::WriteBuffer).not_to receive(:add)
        expect(::AuditEvents::AiAuditEvents::Streamer).not_to receive(:stream)
        expect(Gitlab::AuditJsonLogger).not_to receive(:build)

        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

        service.execute
      end

      context 'when the events are neither stored nor streamed' do
        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: false)
        end

        it 'does not enqueue ProcessAuditEventsWorker' do
          expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to receive(:perform_async)

          expect(service.execute.payload).to eq({ status: 'accepted', count: 2 })
        end

        it 'does not enqueue ProcessAuditEventsWorker when the project and namespace are gone' do
          allow(workflow).to receive_messages(project: nil, namespace: nil)

          expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'still tracks the ingested batch' do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)

          expect { service.execute }
            .to trigger_internal_events('ingest_ai_audit_events_batch')
            .with(project: project, additional_properties: { value: 2, property: 'postgresql' })
        end

        context 'when the workflow has no project and storage is off for its namespace' do
          let_it_be(:group) { create(:group) }
          let_it_be(:namespace_workflow) do
            create(:duo_workflows_workflow, user: user, project: nil, namespace: group)
          end

          subject(:service) do
            described_class.new(workflow: namespace_workflow, events: events, current_user: user)
          end

          it 'does not enqueue ProcessAuditEventsWorker' do
            expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to receive(:perform_async)

            service.execute
          end

          context 'when AI audit event streaming is on for the organization' do
            before do
              ::Ai::Setting.for_organization(group.organization).update!(ai_audit_events_streaming_enabled: true)
            end

            it 'enqueues ProcessAuditEventsWorker' do
              expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

              service.execute
            end
          end
        end

        context 'when AI audit event streaming is on for the organization' do
          before do
            ::Ai::Setting.for_organization(project.organization).update!(ai_audit_events_streaming_enabled: true)
          end

          it 'enqueues ProcessAuditEventsWorker' do
            expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

            service.execute
          end
        end

        context 'when storage is on for the namespace of a workflow without a project' do
          let_it_be(:group) { create(:group) }
          let_it_be(:namespace_workflow) do
            create(:duo_workflows_workflow, user: user, project: nil, namespace: group)
          end

          subject(:service) do
            described_class.new(workflow: namespace_workflow, events: events, current_user: user)
          end

          before do
            group.reload.namespace_settings.update!(ai_audit_events_storage_enabled: true)
          end

          it 'enqueues ProcessAuditEventsWorker' do
            expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

            service.execute
          end
        end
      end

      it 'skips events without an id' do
        events << { type: 'ai_tool_invoked', source: '/duo_workflow_service', time: event_time_one, data: {} }

        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
          .to receive(:perform_async).with(array_including(have_attributes(size: 2).or(be_a(Hash))))

        result = service.execute

        expect(result.payload[:count]).to eq(2)
      end

      it 'skips events with blank type' do
        events << { id: SecureRandom.uuid, type: '', source: '/duo_workflow_service', time: event_time_one }

        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

        result = service.execute

        expect(result.payload[:count]).to eq(2)
      end

      it 'skips events missing time rather than fabricating a timestamp' do
        events << { id: SecureRandom.uuid, type: 'ai_tool_invoked', source: '/duo_workflow_service', data: {} }

        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

        result = service.execute

        expect(result.payload[:count]).to eq(2)
      end

      it 'does not enqueue the worker when no events pass validation' do
        events.clear

        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to receive(:perform_async)

        service.execute
      end

      context 'when the flow keeps only metadata' do
        let_it_be(:workflow) do
          create(:duo_workflows_workflow, user: user, project: project,
            workflow_definition: ::Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE)
        end

        let(:events) do
          [
            {
              id: event_id_one,
              type: 'ai_llm_input_sent',
              source: '/duo_workflow_service',
              time: event_time_one,
              data: { model_name: 'claude', prompt_token_count: 12, prompt_content: 'the prompt',
                      response_content: 'the answer', tool_args: '{"path":"secret.rb"}', error_message: 'boom' }
            }
          ]
        end

        it 'keeps only metadata in the stored details', :aggregate_failures do
          details = details_of(capture_enqueued_attributes).first

          expect(details).to include(model_name: 'claude', prompt_token_count: 12)
          expect(details.keys).not_to include('prompt_content', 'response_content', 'tool_args', 'error_message')
        end
      end

      context 'when the workflow is an external agent governance session' do
        let_it_be(:session) do
          create(:ai_governance_session, :external, namespace: project.project_namespace, project: project,
            user: user)
        end

        let(:events) do
          [
            {
              id: event_id_one,
              type: 'ai_llm_input_sent',
              source: '/duo_workflow_service',
              time: event_time_one,
              data: { model_name: 'claude', prompt_content: 'the prompt' }
            }
          ]
        end

        subject(:service) do
          described_class.new(workflow: session, governance_session_id: session.id, events: events,
            current_user: user)
        end

        it 'keeps the full content in the stored details' do
          details = details_of(capture_enqueued_attributes).first

          expect(details).to include(model_name: 'claude', prompt_content: 'the prompt')
        end
      end

      context 'with ip_address attribution' do
        let(:payload_ip) { '198.51.100.7' }
        let(:events) do
          [
            {
              id: event_id_one,
              type: 'ai_llm_input_sent',
              source: '/duo_workflow_service',
              time: event_time_one,
              data: { ip_address: payload_ip, model: 'claude-3' }
            }
          ]
        end

        context 'when the user has a current_sign_in_ip' do
          before do
            allow(user).to receive(:current_sign_in_ip).and_return('203.0.113.42')
          end

          it 'attributes the user sign-in IP, overriding the executor IP from the payload' do
            enqueued_attributes = capture_enqueued_attributes.first

            expect(enqueued_attributes['ip_address'].to_s).to eq('203.0.113.42')
            expect(enqueued_attributes['details'].with_indifferent_access[:ip_address]).to eq('203.0.113.42')
          end
        end

        context 'when the user has no current_sign_in_ip' do
          before do
            allow(user).to receive(:current_sign_in_ip).and_return(nil)
          end

          it 'records nil rather than the executor IP carried in the payload' do
            enqueued_attributes = capture_enqueued_attributes.first

            expect(enqueued_attributes['ip_address']).to be_nil
            expect(enqueued_attributes['details'].with_indifferent_access[:ip_address]).to be_nil
          end
        end
      end

      context 'with composite identity attribution', :request_store do
        let_it_be(:service_account) { create(:user, :ai_service_account) }
        let_it_be(:human) { create(:user) }

        context 'when the current user is a human resolved from a composite identity token' do
          subject(:service) do
            described_class.new(workflow: workflow, events: events, current_user: human)
          end

          before do
            ::Gitlab::Auth::Identity.link_from_scoped_user(service_account, human, context: :authentication)
          end

          it 'attributes author_id to the service account and records human author details', :aggregate_failures do
            enqueued_attributes = capture_enqueued_attributes

            expect(enqueued_attributes).to all(include('author_id' => service_account.id))
            expect(details_of(enqueued_attributes)).to all(include(
              human_author_id: human.id,
              human_author_name: human.name,
              human_author_username: human.username
            ))
          end

          context 'when the payload data carries human author keys' do
            let(:events) do
              [
                {
                  id: event_id_one,
                  type: 'ai_llm_input_sent',
                  source: '/duo_workflow_service',
                  time: event_time_one,
                  data: { 'human_author_id' => non_existing_record_id, human_author_username: 'spoofed' }
                }
              ]
            end

            it 'replaces them with the server-side resolved human regardless of key type' do
              enqueued_details = details_of(capture_enqueued_attributes)

              expect(enqueued_details.first).to include(
                human_author_id: human.id,
                human_author_username: human.username
              )
            end
          end
        end

        context 'when the service account is linked in the permission_check context' do
          subject(:service) do
            described_class.new(workflow: workflow, events: events, current_user: human)
          end

          before do
            ::Gitlab::Auth::Identity.link_from_scoped_user(service_account, human, context: :permission_check)
          end

          it 'keeps author_id on the human without human author details', :aggregate_failures do
            enqueued_attributes = capture_enqueued_attributes

            expect(enqueued_attributes).to all(include('author_id' => human.id))
            details_of(enqueued_attributes).each do |details|
              expect(details.keys).not_to include('human_author_id', 'human_author_name', 'human_author_username')
            end
          end
        end

        context 'when the current user is a service account without a composite identity link' do
          subject(:service) do
            described_class.new(workflow: workflow, events: events, current_user: service_account)
          end

          it 'attributes author_id to the service account without human author details', :aggregate_failures do
            enqueued_attributes = capture_enqueued_attributes

            expect(enqueued_attributes).to all(include('author_id' => service_account.id))
            details_of(enqueued_attributes).each do |details|
              expect(details.keys).not_to include('human_author_id', 'human_author_name', 'human_author_username')
            end
          end
        end

        context 'when the current user is a regular user' do
          it 'does not record human author details' do
            details_of(capture_enqueued_attributes).each do |details|
              expect(details.keys).not_to include('human_author_id', 'human_author_name', 'human_author_username')
            end
          end

          context 'when the payload data carries human author keys' do
            let(:events) do
              [
                {
                  id: event_id_one,
                  type: 'ai_llm_input_sent',
                  source: '/duo_workflow_service',
                  time: event_time_one,
                  data: { 'human_author_id' => non_existing_record_id, human_author_name: 'spoofed' }
                }
              ]
            end

            it 'strips them instead of passing them through as authoritative' do
              enqueued_details = details_of(capture_enqueued_attributes)

              expect(enqueued_details.first.keys)
                .not_to include('human_author_id', 'human_author_name', 'human_author_username')
            end
          end
        end
      end

      context 'when events is nil' do
        subject(:service) do
          described_class.new(
            workflow: workflow,
            events: nil,
            current_user: user
          )
        end

        it 'returns success with count 0 without raising' do
          result = service.execute

          expect(result).to be_success
          expect(result.payload).to eq({ status: 'accepted', count: 0 })
        end
      end

      context 'when batch exceeds max size' do
        let(:events) do
          Array.new(501) do
            { id: SecureRandom.uuid, type: 'ai_llm_input_sent', source: '/', time: event_time_one }
          end
        end

        it 'returns an error without enqueuing' do
          expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to receive(:perform_async)

          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:bad_request)
        end
      end

      context 'when an event has an unknown type name' do
        let(:events) do
          [
            {
              id: SecureRandom.uuid,
              type: 'ai_llm_input_sent',
              source: '/duo_workflow_service',
              time: event_time_one,
              data: {}
            },
            {
              id: SecureRandom.uuid,
              type: 'totally_made_up_event',
              source: '/duo_workflow_service',
              time: event_time_two,
              data: {}
            }
          ]
        end

        it 'enqueues only the known event and reports the dropped type' do
          enqueued_attrs = nil
          allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
            .to receive(:perform_async) { |attrs| enqueued_attrs = attrs }

          result = service.execute

          expect(result).to be_success
          expect(result.payload).to eq({
            status: 'accepted',
            count: 1,
            dropped_unknown_event_types: ['totally_made_up_event']
          })
          expect(enqueued_attrs.size).to eq(1)
          expect(enqueued_attrs.first['event_name']).to eq('ai_llm_input_sent')
        end

        it 'reports every unknown name once, sorted, in the response payload' do
          events << {
            id: SecureRandom.uuid,
            type: 'another_bogus_type',
            source: '/duo_workflow_service',
            time: event_time_two,
            data: {}
          }

          # Same unknown name twice should be deduplicated in the response
          events << {
            id: SecureRandom.uuid,
            type: 'totally_made_up_event',
            source: '/duo_workflow_service',
            time: event_time_two,
            data: {}
          }

          allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

          result = service.execute

          expect(result).to be_success
          expect(result.payload[:dropped_unknown_event_types]).to eq(
            %w[another_bogus_type totally_made_up_event]
          )
        end
      end

      context 'with Prometheus metrics' do
        describe 'INGESTED_COUNTER' do
          before do
            allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
          end

          it 'increments with event_name: for each valid event' do
            expect(described_class::INGESTED_COUNTER)
              .to receive(:increment).with(event_name: 'ai_llm_input_sent').once
            expect(described_class::INGESTED_COUNTER)
              .to receive(:increment).with(event_name: 'ai_llm_response_received').once

            service.execute
          end
        end

        describe 'DROPPED_COUNTER with reason: :malformed' do
          let(:malformed_events) do
            [
              { type: 'ai_llm_input_sent', source: '/', time: event_time_one },
              { id: event_id_one, source: '/', time: event_time_one },
              { id: event_id_two, type: 'ai_llm_input_sent', source: '/' }
            ]
          end

          subject(:service) do
            described_class.new(workflow: workflow, events: malformed_events, current_user: user)
          end

          before do
            allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
            allow(ClickHouse::WriteBuffer).to receive(:add)
          end

          it 'increments DROPPED_COUNTER with reason: :malformed for each malformed event' do
            expect(described_class::DROPPED_COUNTER)
              .to receive(:increment).with(reason: :malformed).exactly(3).times

            service.execute
          end
        end

        describe 'DROPPED_COUNTER with reason: :unknown_event' do
          let(:events_with_unknown) do
            [
              {
                id: event_id_one,
                type: 'totally_made_up_event',
                source: '/duo_workflow_service',
                time: event_time_one,
                data: {}
              },
              {
                id: event_id_two,
                type: 'another_bogus_type',
                source: '/duo_workflow_service',
                time: event_time_two,
                data: {}
              }
            ]
          end

          subject(:service) do
            described_class.new(workflow: workflow, events: events_with_unknown, current_user: user)
          end

          before do
            allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
            allow(ClickHouse::WriteBuffer).to receive(:add)
          end

          it 'increments DROPPED_COUNTER with reason: :unknown_event for each unknown-type event' do
            expect(described_class::DROPPED_COUNTER)
              .to receive(:increment).with(reason: :unknown_event).twice

            service.execute
          end
        end
      end

      context 'with internal event tracking' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        it 'fires the ingest_ai_audit_events_batch event with correct properties when events are stored' do
          expect { service.execute }
            .to trigger_internal_events('ingest_ai_audit_events_batch')
            .with(
              project: project,
              additional_properties: {
                value: 2,
                property: 'postgresql'
              }
            )
        end

        it 'increments the ingested totals metrics by the batch size' do
          expect { service.execute }
            .to increment_usage_metrics(
              'counts.count_total_ai_audit_events_ingested_weekly',
              'counts.count_total_ai_audit_events_ingested_monthly',
              'counts.count_total_ai_audit_events_ingested'
            ).by(2)
        end

        context 'when ClickHouse is globally enabled for analytics' do
          before do
            allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
            allow(ClickHouse::WriteBuffer).to receive(:add)
          end

          it 'fires the event with property: clickhouse' do
            expect { service.execute }
              .to trigger_internal_events('ingest_ai_audit_events_batch')
              .with(
                project: project,
                additional_properties: {
                  value: 2,
                  property: 'clickhouse'
                }
              )
          end
        end

        context 'when all events are dropped (empty batch after build)' do
          subject(:service) do
            described_class.new(workflow: workflow, events: [], current_user: user)
          end

          it 'does not fire the internal event for an empty batch' do
            expect { service.execute }.not_to trigger_internal_events('ingest_ai_audit_events_batch')
          end
        end
      end

      context 'when every name in the batch is in the allowlist' do
        it 'accepts every name listed in AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES' do
          batch = ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.each_with_index.map do |name, idx|
            {
              id: SecureRandom.uuid,
              type: name,
              source: '/duo_workflow_service',
              time: event_time_one + idx.seconds,
              data: {}
            }
          end

          allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)

          result = described_class.new(
            workflow: workflow, events: batch, current_user: user
          ).execute

          expect(result).to be_success
          expect(result.payload[:count]).to eq(batch.size)
        end
      end
    end
  end

  describe '#workflow_id' do
    it 'returns nil when governance_session_id is present' do
      service = described_class.new(workflow: workflow, governance_session_id: 999, events: [], current_user: user)
      expect(service.send(:workflow_id)).to be_nil
    end

    it 'returns workflow id when governance_session_id is absent' do
      service = described_class.new(workflow: workflow, events: [], current_user: user)
      expect(service.send(:workflow_id)).to eq(workflow.id)
    end
  end

  def capture_enqueued_attributes
    captured = nil
    allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
      .to receive(:perform_async) { |attrs| captured = attrs }

    service.execute

    captured
  end

  def details_of(attributes)
    attributes.map { |attrs| attrs['details'].with_indifferent_access }
  end
end
