# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumers::BulkCreateService, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group, owners: current_user) }
  let_it_be(:project_1) { create(:project, group: group, maintainers: current_user) }
  let_it_be(:project_2) { create(:project, group: group, maintainers: current_user) }
  let_it_be(:item) { create(:ai_catalog_agent, :with_released_version, :public) }

  let(:projects) { Project.id_in([project_1.id, project_2.id]) }
  let(:trigger_types) { nil }
  let(:trigger_filter) { nil }
  let(:trigger_goals) { nil }
  let(:pinned_version) { nil }

  subject(:execute) do
    described_class.new(current_user:, item:, projects:, trigger_types:, trigger_filter:, trigger_goals:,
      pinned_version:).execute
  end

  before do
    enable_ai_catalog
  end

  shared_examples 'logs the failure' do
    it 'logs the failure' do
      mock_logger = Ai::Catalog::Logger.build
      allow(Ai::Catalog::Logger).to receive(:build).and_return(mock_logger)
      allow(mock_logger).to receive(:context).and_return(mock_logger)

      expect(mock_logger).to receive(:context).with(item:)
      expect(mock_logger).to receive(:error).with(
        message: 'Failed to create item consumer for project',
        project_id: failed_project.id,
        error_message: failure_message
      )

      execute
    end
  end

  it 'creates item consumers for each project and returns success' do
    expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(3)
      .and not_change { Ai::FlowTrigger.count }

    expect(Ai::Catalog::ItemConsumer.exists?(group: group, ai_catalog_item_id: item.id, kind: :direct)).to be true
    expect(Ai::Catalog::ItemConsumer.exists?(project: project_1, ai_catalog_item_id: item.id, kind: :direct)).to be true
    expect(Ai::Catalog::ItemConsumer.exists?(project: project_2, ai_catalog_item_id: item.id, kind: :direct)).to be true
    expect(execute).to be_success
    expect(execute.payload[:failures]).to be_empty
    expect(execute.payload[:successful_count]).to eq(2)
  end

  context 'when trigger_types are provided for a flow item' do
    let(:item) { create(:ai_catalog_flow, :with_released_version, :public) }
    let(:trigger_types) { ['mention'] }

    it 'creates item consumers with flow triggers for each project' do
      expect { execute }.to change { Ai::Catalog::ItemConsumer.count }
        .and change { Ai::FlowTrigger.count }.by(2)

      consumer = Ai::Catalog::ItemConsumer.last
      expect(consumer.flow_trigger.event_types).to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
    end

    context 'when trigger_goals is also provided' do
      let(:trigger_goals) { { 'mention' => 'Summarise the thread.' } }

      it 'creates item consumers with the trigger goals for each project', :aggregate_failures do
        expect { execute }.to change { Ai::FlowTrigger.count }.by(2)

        expect(Ai::FlowTrigger.last(2).map(&:goals)).to all(eq(trigger_goals))
      end

      # The flag is a per-project actor, so EnqueueBulkCreateService cannot refuse the
      # batch up front. Each project has to fail with a message the result email can show.
      context 'when the goals feature flag is disabled' do
        before do
          stub_feature_flags(ai_flow_trigger_goals: false)
        end

        it 'fails every project with a readable message', :aggregate_failures do
          expect { execute }.not_to change { Ai::FlowTrigger.count }

          expect(execute.payload[:failures].map { |failure| failure[:error_message] })
            .to all(include('Flow trigger goals are not available'))
        end
      end
    end

    context 'when trigger_filter is also provided' do
      let(:trigger_types) { %w[pipeline_hooks] }
      let(:trigger_filter) do
        {
          'pipeline_hooks' => {
            'rules' => [
              { 'field' => 'object_attributes.status', 'operator' => 'in', 'value' => %w[success failed] }
            ]
          }
        }
      end

      it 'creates item consumers with the trigger filter for each project', :aggregate_failures do
        expect { execute }.to change { Ai::Catalog::ItemConsumer.count }
          .and change { Ai::FlowTrigger.count }.by(2)

        consumer = Ai::Catalog::ItemConsumer.find_by(project: project_1, ai_catalog_item_id: item.id)
        expect(consumer.flow_trigger.filter).to eq(trigger_filter)
      end
    end

    # An autonomous trigger needs an account of its own, and the accounts are
    # project-scoped, so a bulk create provisions one per project rather than
    # sharing a single account across all of them.
    context 'when the trigger type is autonomous' do
      let(:trigger_types) { %w[scheduled] }
      let(:trigger_filter) do
        { 'scheduled' => { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 } }
      end

      it 'provisions a separate dedicated account for every project', :aggregate_failures do
        expect { execute }.to change { Ai::FlowTrigger.count }.by(2)

        triggers = [project_1, project_2].map do |project|
          Ai::Catalog::ItemConsumer.find_by(project: project, ai_catalog_item_id: item.id).flow_trigger
        end

        accounts = triggers.map(&:autonomous_service_account)
        expect(accounts).to all(be_service_account)
        expect(accounts.map(&:id).uniq.size).to eq(2)

        triggers.each_with_index do |trigger, index|
          expect(trigger.project.team.member?(accounts[index])).to be(true)
        end
      end
    end
  end

  context 'when pinned_version is provided' do
    let(:pinned_version) { '1.2.3' }

    before do
      create(:ai_catalog_agent_version, :released, item: item.class.find(item.id), version: '1.2.3')
      create(:ai_catalog_agent_version, :released, item: item.class.find(item.id), version: '2.3.4')
    end

    it 'creates item consumers pinned to the specified version', :aggregate_failures do
      expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(3)

      [project_1, project_2].each do |project|
        consumer = Ai::Catalog::ItemConsumer.find_by(project: project, ai_catalog_item_id: item.id)
        expect(consumer.pinned_version_prefix).to eq('1.2.3')
      end
    end
  end

  context 'when a consumer fails to be created for a project' do
    let_it_be(:unauthorized_project) { create(:project, :in_group) }

    let(:projects) { Project.id_in([project_1.id, unauthorized_project.id]) }

    it 'tracks successes and failures in results', :aggregate_failures do
      expect(execute).to be_success
      expect(execute.payload[:successful_count]).to eq(1)
      expect(execute.payload[:failures]).to include(
        a_hash_including(
          project_id: unauthorized_project.id,
          error_message: "You don't have permission to enable this agent or flow, or it doesn't exist"
        )
      )
    end

    it_behaves_like 'logs the failure' do
      let(:failed_project) { unauthorized_project }
      let(:failure_message) { "You don't have permission to enable this agent or flow, or it doesn't exist" }
    end
  end

  context 'when a consumer is created with a warning' do
    before do
      allow_next_instances_of(::Ai::Catalog::ItemConsumers::CreateService, 2) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.success(
            payload: {
              item_consumer: build(:ai_catalog_item_consumer),
              warnings: ['the scheduled trigger was skipped']
            }
          )
        )
      end
    end

    it 'reports the warning per project without counting it as a failure', :aggregate_failures do
      expect(execute).to be_success
      expect(execute.payload[:failures]).to be_empty
      expect(execute.payload[:successful_count]).to eq(2)
      expect(execute.payload[:warnings]).to contain_exactly(
        { project_id: project_1.id, message: 'the scheduled trigger was skipped' },
        { project_id: project_2.id, message: 'the scheduled trigger was skipped' }
      )
    end

    it 'logs each warning' do
      mock_logger = Ai::Catalog::Logger.build
      allow(Ai::Catalog::Logger).to receive(:build).and_return(mock_logger)
      allow(mock_logger).to receive(:context).and_return(mock_logger)

      expect(mock_logger).to receive(:warn).with(
        message: 'Partially created item consumer for project',
        project_id: project_1.id,
        warning_message: 'the scheduled trigger was skipped'
      )
      expect(mock_logger).to receive(:warn).with(
        message: 'Partially created item consumer for project',
        project_id: project_2.id,
        warning_message: 'the scheduled trigger was skipped'
      )

      execute
    end
  end

  context 'when a consumer is already configured for the projects' do
    before do
      described_class.new(current_user:, item:, projects:).execute
    end

    it 'counts the already configured projects as successes', :aggregate_failures do
      expect { execute }.not_to change { Ai::Catalog::ItemConsumer.count }

      expect(execute).to be_success
      expect(execute.payload[:successful_count]).to eq(2)
      expect(execute.payload[:failures]).to be_empty
    end
  end

  context 'when the projects already inherit the item from the top-level group' do
    let_it_be(:item) { create(:ai_catalog_flow, :with_released_version, :public) }

    before_all do
      create(:ai_catalog_item_consumer, :inheritance, group: group, item: item)
    end

    it 'counts the inheriting projects as successes', :aggregate_failures do
      expect { execute }.not_to change { Ai::Catalog::ItemConsumer.count }

      expect(execute).to be_success
      expect(execute.payload[:successful_count]).to eq(2)
      expect(execute.payload[:failures]).to be_empty
    end
  end

  context 'when the create service raises an exception' do
    let(:projects) { Project.id_in([project_1.id]) }

    before do
      allow(::Ai::Catalog::ItemConsumers::CreateService).to receive(:new).and_raise(StandardError, 'unexpected error')
    end

    it 'catches the exception and adds it to failures', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(StandardError),
        project_id: project_1.id,
        item_id: item.id
      )

      expect(execute).to be_success
      expect(execute.payload[:successful_count]).to eq(0)
      expect(execute.payload[:failures]).to contain_exactly(
        a_hash_including(
          project_id: project_1.id,
          error_message: 'Something went wrong on our end whilst processing this project'
        )
      )
    end

    it_behaves_like 'logs the failure' do
      let(:failed_project) { project_1 }
      let(:failure_message) { 'Something went wrong on our end whilst processing this project' }
    end
  end
end
