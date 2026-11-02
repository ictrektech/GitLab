# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillMissingRecommendReviewersAiFlowTriggers,
  migration: :gitlab_main_org,
  feature_category: :duo_agent_platform do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:users) { table(:users) }
  let(:ai_catalog_items) { table(:ai_catalog_items) }
  let(:ai_catalog_item_consumers) { table(:ai_catalog_item_consumers) }
  let(:ai_flow_triggers) { table(:ai_flow_triggers) }

  let(:mention) { 0 }
  let(:merge_request) { 6 }
  let(:inheritance) { 1 }

  let(:created_filter) do
    { 'merge_request' => { 'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => ['created'] }] } }
  end

  let!(:organization) { organizations.create!(name: 'Organization 1', path: 'organization-1') }
  let!(:group) do
    namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id)
  end

  let!(:project) { create_project('project') }
  let!(:recommend_reviewers_item) { create_item('recommend_reviewers/v1', 'Recommend Reviewers') }
  let!(:group_consumer) do
    ai_catalog_item_consumers.create!(ai_catalog_item_id: recommend_reviewers_item.id, group_id: group.id,
      service_account_id: create_user('service-account').id)
  end

  def create_project(path)
    project_namespace = namespaces.create!(name: path, path: path, type: 'Project', parent_id: group.id,
      organization_id: organization.id)

    projects.create!(name: path, path: path, namespace_id: group.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id)
  end

  def create_user(username)
    users.create!(username: username, email: "#{username}@example.com", projects_limit: 0,
      organization_id: organization.id)
  end

  def create_item(reference, name)
    ai_catalog_items.create!(
      name: name,
      description: 'A foundational flow',
      visibility: 2,
      organization_id: organization.id,
      item_type: 2,
      foundational_flow_reference: reference
    )
  end

  def create_consumer(item: recommend_reviewers_item, project: self.project, **attributes)
    ai_catalog_item_consumers.create!(ai_catalog_item_id: item.id, project_id: project.id,
      parent_item_consumer_id: group_consumer.id, **attributes)
  end

  def create_trigger(consumer, event_types: [merge_request])
    ai_flow_triggers.create!(project_id: consumer.project_id, description: 'A trigger',
      ai_catalog_item_consumer_id: consumer.id, event_types: event_types)
  end

  def triggers_for(consumer)
    ai_flow_triggers.where(ai_catalog_item_consumer_id: consumer.id)
  end

  describe '#up' do
    it 'creates the trigger for a consumer without one', :aggregate_failures do
      consumer = create_consumer

      migrate!

      trigger = triggers_for(consumer).sole
      expect(trigger).to have_attributes(
        project_id: project.id,
        description: 'Foundational flow trigger for Recommend Reviewers',
        event_types: [merge_request],
        filter: created_filter,
        user_id: nil,
        active: true
      )
    end

    it 'creates triggers in every batch' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      consumers = [create_consumer, create_consumer(project: create_project('project-2'))]

      migrate!

      expect(consumers.map { |consumer| triggers_for(consumer).count }).to match_array([1, 1])
    end

    it 'creates the trigger for a consumer with its own service account' do
      consumer = create_consumer(parent_item_consumer_id: nil, service_account_id: create_user('own-account').id)

      expect { migrate! }.to change { triggers_for(consumer).count }.from(0).to(1)
    end

    it 'creates the trigger when the consumer has a trigger for another event only' do
      consumer = create_consumer
      create_trigger(consumer, event_types: [mention])

      expect { migrate! }.to change { triggers_for(consumer).count }.from(1).to(2)
    end

    it 'does not create a trigger when the consumer has a merge request trigger' do
      consumer = create_consumer
      create_trigger(consumer, event_types: [mention, merge_request])

      expect { migrate! }.not_to change { triggers_for(consumer).count }.from(1)
    end

    it 'creates one trigger, on the oldest consumer, for duplicate consumers of a project' do
      older_consumer = create_consumer
      newer_consumer = create_consumer

      migrate!

      expect([triggers_for(older_consumer).count, triggers_for(newer_consumer).count]).to eq([1, 0])
    end

    it 'creates one trigger for duplicate consumers of a project in different batches' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      older_consumer = create_consumer
      newer_consumer = create_consumer

      migrate!

      expect([triggers_for(older_consumer).count, triggers_for(newer_consumer).count]).to eq([1, 0])
    end

    it 'does not create a trigger when a duplicate consumer of the project has a merge request trigger' do
      older_consumer = create_consumer
      newer_consumer = create_consumer
      create_trigger(newer_consumer)

      expect { migrate! }.not_to change { ai_flow_triggers.count }.from(1)
      expect(triggers_for(older_consumer)).to be_empty
    end

    it 'does not create a trigger when the consumer has no active service account' do
      consumer = create_consumer(parent_item_consumer_id: nil)

      expect { migrate! }.not_to change { triggers_for(consumer).count }.from(0)
    end

    it 'does not create a trigger for an inheritance consumer' do
      consumer = create_consumer(kind: inheritance)

      expect { migrate! }.not_to change { triggers_for(consumer).count }.from(0)
    end

    it 'does not create a trigger for a group consumer' do
      expect { migrate! }.not_to change { triggers_for(group_consumer).count }.from(0)
    end

    it 'does not create a trigger for consumers of other flows' do
      consumer = create_consumer(item: create_item('risk_classification/v1', 'Risk Classification'))

      expect { migrate! }.not_to change { triggers_for(consumer).count }.from(0)
    end

    it 'is idempotent' do
      consumer = create_consumer

      migrate!
      schema_migrate_down!
      migrate!

      expect(triggers_for(consumer).count).to eq(1)
    end
  end
end
