# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectTrackedContexts::FindOrCreateService, :delete,
  feature_category: :vulnerability_management do
  # Separate connections need committed records; :delete cleanup is incompatible with let_it_be.
  let(:project) { create(:project) }
  let(:context_model) { Security::ProjectTrackedContext }
  let(:lock_sql) do
    "SELECT pg_try_advisory_xact_lock(" \
      "hashtextextended('security:project_tracked_contexts:#{project.id}:default', 0))"
  end

  before do
    allow(project).to receive_messages(default_branch: 'main', default_branch_or_main: 'main')
  end

  def service_for(name = 'main')
    described_class.new(project: project, context_name: name, context_type: :branch, is_default: true)
  end

  def with_competing_connection
    connection = PG.connect(context_model.connection.raw_connection.conninfo_hash.reject { |_, value| value.blank? })
    yield connection
  ensure
    connection&.close
  end

  it 'holds the lock after the service returns until the caller commits', :aggregate_failures do
    with_competing_connection do |other|
      context_model.transaction do
        expect(service_for.execute).to be_success
        expect(other.exec(lock_sql).getvalue(0, 0)).to eq('f')
        expect(other.exec("SELECT count(*) FROM security_project_tracked_contexts " \
          "WHERE project_id = #{project.id}").getvalue(0, 0)).to eq('0')
      end

      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')
      expect(context_model.for_project(project).default_refs.count).to eq(1)
    end
  end

  it 'releases the lock and the created row when the caller rolls back', :aggregate_failures do
    with_competing_connection do |other|
      context_model.transaction do
        expect(service_for.execute).to be_success
        expect(other.exec(lock_sql).getvalue(0, 0)).to eq('f')
        raise ActiveRecord::Rollback
      end

      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')
      expect(context_model.for_project(project)).to be_empty
      expect(service_for.execute).to be_success
    end
  end

  it 'rejects a concurrent default creation and reuses the committed differently named default', :aggregate_failures do
    with_competing_connection do |other|
      other.exec('BEGIN')
      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')
      other.exec("INSERT INTO security_project_tracked_contexts " \
        "(project_id, context_name, context_type, is_default, state, created_at, updated_at) " \
        "VALUES (#{project.id}, 'old-main', 1, true, 2, NOW(), NOW())")

      context_model.transaction do
        result = service_for.execute
        expect(result.reason).to eq(:tracked_context_busy)
        expect(context_model.connection.select_value('SELECT 1')).to eq(1)
      end

      other.exec('COMMIT')
      result = service_for.execute

      expect(result).to be_success
      expect(result.payload[:tracked_context].context_name).to eq('main')
      expect(context_model.for_project(project).default_refs.count).to eq(1)
    end
  end

  it 'does not reuse a cached miss after another connection commits', :aggregate_failures do
    service = service_for

    with_competing_connection do |other|
      allow(service).to receive(:obtain_lock).and_wrap_original do |method|
        other.exec("INSERT INTO security_project_tracked_contexts " \
          "(project_id, context_name, context_type, is_default, state, created_at, updated_at) " \
          "VALUES (#{project.id}, 'old-main', 1, true, 2, NOW(), NOW())")
        method.call
      end

      context_model.cache do
        expect(project.security_project_tracked_contexts.default_branch.last).to be_nil
        expect(service.execute).to be_success
      end

      expect(context_model.for_project(project).default_refs.count).to eq(1)
    end
  end

  it 'does not reuse a cached successful lock result in a later transaction', :aggregate_failures do
    with_competing_connection do |other|
      context_model.cache do
        context_model.transaction { context_model.connection.select_value(lock_sql) }
        other.exec('BEGIN')
        expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')

        expect(service_for.execute.reason).to eq(:tracked_context_busy)
        expect(context_model.for_project(project)).to be_empty
      end
    end
  end

  it 'allows another project to create a context while this project is locked', :aggregate_failures do
    other_project = create(:project)

    with_competing_connection do |other|
      other.exec('BEGIN')
      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')

      result = described_class.new(project: other_project, context_name: 'main',
        context_type: :branch, is_default: true).execute

      expect(result).to be_success
    end
  end

  it 'allows an unrelated non-default ref while the default is locked', :aggregate_failures do
    with_competing_connection do |other|
      other.exec('BEGIN')
      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')

      result = described_class.new(project: project, context_name: 'feature',
        context_type: :branch, is_default: false, allow_untracked: true).execute

      expect(result).to be_success
      expect(result.payload[:tracked_context]).to be_untracked
    end
  end

  it 'rolls back the caller on a collision after validation and allows a fresh attempt', :aggregate_failures do
    default_context = create(:security_project_tracked_context, :default,
      project: project, context_name: 'old-main')
    service = service_for
    competing_id = nil

    with_competing_connection do |other|
      allow(service).to receive(:existing_default_branch_context).and_return(default_context)
      # Insert after uniqueness validation so the UPDATE hits the database constraint.
      # RecordNotUnique must escape the caller's transaction so it rolls back before any retry.
      allow(default_context).to receive(:_update_record).and_wrap_original do |method, *args|
        competing_id = other.exec("INSERT INTO security_project_tracked_contexts " \
          "(project_id, context_name, context_type, is_default, state, created_at, updated_at) " \
          "VALUES (#{project.id}, 'main', 1, false, 2, NOW(), NOW()) RETURNING id").getvalue(0, 0).to_i
        method.call(*args)
      end

      expect do
        context_model.transaction do
          create(:security_project_tracked_context, :untracked, project: project, context_name: 'caller-write')
          service.execute
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect(default_context.reload.context_name).to eq('old-main')
      expect(context_model.for_project(project).for_context_name('caller-write')).to be_empty
      expect(context_model.for_project(project).default_refs.count).to eq(1)
      expect(other.exec(lock_sql).getvalue(0, 0)).to eq('t')

      result = service_for.execute

      expect(result).to be_success
      expect(result.payload[:tracked_context].id).to eq(competing_id)
    end
  end

  it 'reuses a destination inserted before rename validation', :aggregate_failures do
    default_context = create(:security_project_tracked_context, :default,
      project: project, context_name: 'old-main')
    service = service_for
    competing_id = nil

    with_competing_connection do |other|
      # Insert before update! runs validation: RecordInvalid leaves the transaction usable,
      # so the service can query and reuse the competing row without a savepoint.
      allow(service).to receive(:updated_default_branch_context).and_wrap_original do |method|
        competing_id = other.exec("INSERT INTO security_project_tracked_contexts " \
          "(project_id, context_name, context_type, is_default, state, created_at, updated_at) " \
          "VALUES (#{project.id}, 'main', 1, false, 2, NOW(), NOW()) RETURNING id").getvalue(0, 0).to_i
        method.call
      end

      result = service.execute

      expect(result).to be_success
      expect(result.payload[:tracked_context].id).to eq(competing_id)
      expect(default_context.reload.context_name).to eq('old-main')
    end
  end

  it 'reuses a context inserted before creation validation', :aggregate_failures do
    service = service_for
    competing_id = nil

    with_competing_connection do |other|
      allow(service).to receive(:create_context).and_wrap_original do |method|
        competing_id = other.exec("INSERT INTO security_project_tracked_contexts " \
          "(project_id, context_name, context_type, is_default, state, created_at, updated_at) " \
          "VALUES (#{project.id}, 'main', 1, false, 2, NOW(), NOW()) RETURNING id").getvalue(0, 0).to_i
        method.call
      end

      result = service.execute

      expect(result).to be_success
      expect(result.payload[:tracked_context].id).to eq(competing_id)
      expect(context_model.for_project(project).count).to eq(1)
    end
  end
end
