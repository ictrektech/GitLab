# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillWorkItemAgentPlansContentFile, migration: :gitlab_main_org,
  feature_category: :team_planning do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:issues) { table(:issues) }
  let(:agent_plans) { table(:work_item_agent_plans) }

  let(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let(:namespace) do
    namespaces.create!(name: 'namespace', path: 'namespace', organization_id: organization.id)
  end

  let(:project) do
    projects.create!(
      name: 'project', path: 'project', namespace_id: namespace.id,
      project_namespace_id: namespace.id, organization_id: organization.id
    )
  end

  def create_work_item
    issues.create!(namespace_id: namespace.id, project_id: project.id, work_item_type_id: 1)
  end

  it 'points content_file at the combined payload each row already wrote' do
    plan = agent_plans.create!(
      work_item_id: create_work_item.id, namespace_id: namespace.id, file_store: 2
    )

    migrate!

    plan.reload
    expect(plan.content_file).to eq("#{plan.work_item_id}.json")
    expect(plan.content_file_store).to eq(2)
  end

  it 'leaves rows that already point at a payload alone' do
    plan = agent_plans.create!(
      work_item_id: create_work_item.id, namespace_id: namespace.id,
      file_store: 2, content_file: 'content.json', content_file_store: 1
    )

    migrate!

    plan.reload
    expect(plan.content_file).to eq('content.json')
    expect(plan.content_file_store).to eq(1)
  end

  it 'does not claim a feedback payload exists' do
    plan = agent_plans.create!(work_item_id: create_work_item.id, namespace_id: namespace.id)

    migrate!

    expect(plan.reload.readiness_score_feedback_file).to be_nil
  end
end
