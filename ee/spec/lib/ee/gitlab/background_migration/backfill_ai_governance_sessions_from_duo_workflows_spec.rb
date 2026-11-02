# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillAiGovernanceSessionsFromDuoWorkflows, feature_category: :compliance_management do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:users) { table(:users) }
  let(:workflows) { table(:duo_workflows_workflows) }
  let(:sessions) { table(:ai_governance_sessions) }

  let!(:organization) { organizations.create!(name: 'Organization', path: 'organization') }
  let!(:user) do
    users.create!(email: 'user@example.com', username: 'user', projects_limit: 10, organization_id: organization.id)
  end

  let!(:group) do
    namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id)
  end

  let!(:project_namespace) do
    namespaces.create!(
      name: 'project', path: 'project', type: 'Project', parent_id: group.id, organization_id: organization.id
    )
  end

  let!(:project) do
    projects.create!(
      name: 'project', path: 'project', namespace_id: group.id, project_namespace_id: project_namespace.id,
      organization_id: organization.id
    )
  end

  describe '#perform' do
    let(:started_at) { Time.zone.parse('2026-08-01 10:00:00 UTC') }

    subject(:migration) do
      described_class.new(
        start_cursor: [workflows.minimum(:id)],
        end_cursor: [workflows.maximum(:id)],
        batch_table: :duo_workflows_workflows,
        batch_column: :id,
        sub_batch_size: 2,
        pause_ms: 0,
        connection: ::ApplicationRecord.connection
      )
    end

    def create_workflow(**attrs)
      workflows.create!(
        user_id: user.id, project_id: project.id, status: 3, workflow_definition: 'software_development',
        agent_type: 'duo', environment: 2, created_at: started_at, updated_at: started_at, **attrs
      )
    end

    it 'copies a project workflow using the project namespace' do
      workflow = create_workflow

      migration.perform

      expect(sessions.find_by(workflow_id: workflow.id)).to have_attributes(
        user_id: user.id,
        project_id: project.id,
        namespace_id: project_namespace.id,
        status: 3,
        flow_type: 'software_development',
        agent_type: 'duo',
        source: 0,
        session_started_at: started_at,
        session_finished_at: nil
      )
    end

    it 'copies a namespace workflow using its own namespace' do
      workflow = create_workflow(project_id: nil, namespace_id: group.id)

      migration.perform

      expect(sessions.find_by(workflow_id: workflow.id)).to have_attributes(namespace_id: group.id, project_id: nil)
    end

    it 'copies workflows with no environment or a non-private messaging adapter' do
      no_environment = create_workflow(environment: nil)
      note_adapter = create_workflow(messaging_callback_context: { adapter: 'gitlab_duo_note' })

      migration.perform

      expect(sessions.pluck(:workflow_id)).to contain_exactly(no_environment.id, note_adapter.id)
    end

    it 'skips external and private messaging workflows' do
      create_workflow(environment: described_class::EXTERNAL_ENVIRONMENT)
      create_workflow(messaging_callback_context: { adapter: described_class::PRIVATE_MESSAGING_ADAPTER })

      expect { migration.perform }.not_to change { sessions.count }
    end

    it 'keeps an existing session untouched' do
      workflow = create_workflow
      finished_at = started_at + 1.hour
      existing = sessions.create!(
        workflow_id: workflow.id, user_id: user.id, project_id: project.id, namespace_id: project_namespace.id,
        status: 1, source: 0, session_started_at: started_at, session_finished_at: finished_at
      )

      expect { migration.perform }.not_to change { existing.reload.attributes }
      expect(sessions.count).to eq(1)
    end

    it 'is idempotent' do
      create_workflow
      create_workflow

      migration.perform

      expect { migration.perform }.not_to change { sessions.count }.from(2)
    end
  end

  # Runs the backfill next to the real live sync, so a mapping drift between the two shows up here.
  describe 'parity with the live sync' do
    let!(:workflow_row) do
      workflows.create!(
        user_id: user.id, project_id: project.id, status: 1, workflow_definition: 'software_development',
        agent_type: 'duo', environment: 2
      )
    end

    let(:workflow) { Ai::DuoWorkflows::Workflow.find(workflow_row.id) }

    subject(:migration) do
      described_class.new(
        start_cursor: [workflow_row.id],
        end_cursor: [workflow_row.id],
        batch_table: :duo_workflows_workflows,
        batch_column: :id,
        sub_batch_size: 10,
        pause_ms: 0,
        connection: ::ApplicationRecord.connection
      )
    end

    def session_attributes
      sessions.find_by!(workflow_id: workflow_row.id).attributes.except('id', 'created_at', 'updated_at')
    end

    it 'writes the same row as the live sync' do
      Ai::Governance::Session.sync_from_workflow!(workflow)
      synced = session_attributes
      sessions.delete_all

      migration.perform

      expect(session_attributes).to eq(synced)
    end

    it 'does not duplicate a row the live sync already wrote' do
      Ai::Governance::Session.sync_from_workflow!(workflow)

      expect { migration.perform }.not_to change { sessions.count }.from(1)
    end

    it 'lets the live sync update a backfilled row without duplicating it or resetting session_finished_at' do
      migration.perform
      finished_at = Time.zone.parse('2026-08-01 11:00:00 UTC')
      sessions.update_all(session_finished_at: finished_at)
      workflow_row.update!(status: 3)

      Ai::Governance::Session.sync_from_workflow!(workflow)

      expect(sessions.count).to eq(1)
      expect(sessions.first).to have_attributes(status: 3, session_finished_at: finished_at)
    end
  end
end
