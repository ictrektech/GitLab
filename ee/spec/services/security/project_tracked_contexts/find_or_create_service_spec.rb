# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectTrackedContexts::FindOrCreateService, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :small_repo) }
  let_it_be(:user) { create(:user) }
  let_it_be(:guest_user) { create(:user) }

  let(:context_name) { project.default_branch }
  let(:context_type) { :branch }
  let(:is_default) { true }
  let(:allow_untracked) { false }

  let(:params) do
    {
      project: project,
      context_name: context_name,
      context_type: context_type,
      is_default: is_default,
      allow_untracked: allow_untracked
    }
  end

  subject(:service) { described_class.new(**params) }

  before_all do
    project.add_maintainer(user)
    project.add_guest(guest_user)
  end

  before do
    stub_licensed_features(security_dashboard: true)
    allow(project).to receive(:repository_exists?).and_return(true)
    allow(project.repository).to receive_messages(branch_exists?: true, tag_exists?: true)
  end

  RSpec.shared_examples 'context creation' do
    it 'creates a new tracked context' do
      expect { service.execute }.to change { Security::ProjectTrackedContext.count }.by(1)
    end

    it 'returns success with the created context' do
      expected_state = if allow_untracked
                         Security::ProjectTrackedContext::STATES[:untracked]
                       else
                         Security::ProjectTrackedContext::STATES[:tracked]
                       end

      expect(result).to be_success
      tracked_context = result.payload[:tracked_context]
      expect(tracked_context).to be_persisted
      expect(tracked_context.project).to eq(project)
      expect(tracked_context.context_name).to eq(context_name)
      expect(tracked_context.context_type).to eq(context_type.to_s)
      expect(tracked_context.state).to eq(expected_state)
      expect(tracked_context.is_default).to be(is_default)
      expect(tracked_context.traversal_ids).to eq(project.namespace.traversal_ids)
      expect(tracked_context.uuid_version).to eq(Security::ProjectTrackedContext::CONTEXT_AWARE_UUID_VERSION)
    end

    it 'logs the creation of the tracked context' do
      expect(Gitlab::AppJsonLogger).to receive(:info).with(
        hash_including(
          'class_name' => described_class.name,
          'message' => 'Security tracked context created',
          'gl_project_id' => project.id,
          'context_name' => context_name,
          'context_type' => context_type.to_s,
          'is_default' => is_default
        )
      )

      service.execute
    end

    context 'when creation fails due to validation errors' do
      let(:context_name) { nil }

      it 'returns an error' do
        expect(result).to be_error
        expect(result.message).to eq('Invalid ref name or type specified')
      end

      it 'does not create a tracked context' do
        expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
      end
    end
  end

  RSpec.shared_examples 'existing tracked context' do
    it 'returns success with the existing context' do
      expect(result).to be_success
      expect(result.payload[:tracked_context]).to eq(existing_context)
    end

    it 'does not create a new tracked context' do
      expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
    end

    it 'does not update the existing context' do
      expect { service.execute }.not_to change { existing_context.reload.state }
    end
  end

  describe '.from_pipeline' do
    let_it_be(:pipeline) { create(:ci_pipeline, project: project, ref: 'feature-branch') }

    subject(:service) { described_class.from_pipeline(pipeline) }

    context 'when pipeline is for a branch' do
      it 'initializes service with correct branch parameters' do
        expect(service.project).to eq(project)
        expect(service.context_name).to eq('feature-branch')
        expect(service.context_type).to eq(:branch)
        expect(service.is_default).to be false
      end
    end

    context 'when pipeline is for a tag' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project, ref: 'v1.0.0', tag: true) }

      it 'initializes service with correct tag parameters' do
        expect(service.project).to eq(project)
        expect(service.context_name).to eq('v1.0.0')
        expect(service.context_type).to eq(:tag)
        expect(service.is_default).to be false
      end
    end

    context 'when pipeline is for the default branch' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project, ref: project.default_branch) }

      it 'sets is_default to true' do
        expect(service.is_default).to be true
      end
    end

    context 'when pipeline is an agentic analyzer workload matching the default branch' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123') }

      before do
        allow(Security::AgenticAnalyzer).to receive(:default_branch_scan?).with(pipeline).and_return(true)
      end

      it 'binds to the default branch context', :aggregate_failures do
        expect(service.project).to eq(project)
        expect(service.context_name).to eq(project.default_branch_or_main)
        expect(service.context_type).to eq(:branch)
        expect(service.is_default).to be true
      end
    end

    context 'when pipeline is for a merge request' do
      let_it_be(:merge_request) do
        create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let_it_be(:pipeline) do
        build_stubbed(:ci_pipeline, :detached_merge_request_pipeline, project: project, merge_request: merge_request)
      end

      it 'initializes service with the merge request source branch' do
        expect(service.project).to eq(project)
        expect(service.context_name).to eq('feature')
        expect(service.context_type).to eq(:branch)
        expect(service.is_default).to be false
      end
    end

    context 'when the merge request source branch is the default branch' do
      let_it_be(:merge_request) do
        create(:merge_request,
          source_project: project,
          source_branch: project.default_branch,
          target_branch: 'release-19-3')
      end

      let_it_be(:pipeline) do
        build_stubbed(:ci_pipeline, :detached_merge_request_pipeline, project: project, merge_request: merge_request)
      end

      it 'does not bind to the default branch context', :aggregate_failures do
        expect(service.context_name).to eq(merge_request.ref_path)
        expect(service.is_default).to be false
      end
    end
  end

  describe '.project_default_branch' do
    subject(:service) { described_class.project_default_branch(project) }

    it 'initializes service for the default branch' do
      expect(service.project).to eq(project)
      expect(service.context_name).to eq(project.default_branch)
      expect(service.context_type).to eq(:branch)
      expect(service.is_default).to be(true)
    end
  end

  describe '#execute!' do
    it 'returns the response when the context is not busy' do
      response = service.execute!

      expect(response).to be_success
      expect(response.payload[:tracked_context]).to be_present
    end

    it 'passes other errors through as a response' do
      allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'nope'))

      expect(service.execute!).to be_error
    end

    it 'raises BusyError when another process holds the lock' do
      allow(service).to receive(:execute)
        .and_return(ServiceResponse.error(message: 'Please retry', reason: :tracked_context_busy))

      expect { service.execute! }.to raise_error(Security::ProjectTrackedContexts::BusyError, 'Please retry')
    end
  end

  describe '#execute' do
    subject(:result) { service.execute }

    context 'when current_user is present (GraphQL API usage)' do
      let(:params) do
        {
          project: project,
          context_name: 'feature-branch',
          context_type: :branch,
          is_default: false,
          allow_untracked: false,
          current_user: user
        }
      end

      before do
        allow(project.repository).to receive(:branch_exists?).with('feature-branch').and_return(true)
      end

      context 'when user has permission' do
        it 'allows the operation' do
          expect(result).to be_error
          expect(result.message).to eq('Expected context to already exist for non-default branches')
        end
      end

      context 'when user lacks permission' do
        let(:params) do
          {
            project: project,
            context_name: 'feature-branch',
            context_type: :branch,
            is_default: false,
            allow_untracked: false,
            current_user: guest_user
          }
        end

        it 'returns permission error' do
          expect(result).to be_error
          expect(result.message).to eq('Permission denied')
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end
      end

      context 'when ref validation fails' do
        before do
          allow(project.repository).to receive(:branch_exists?).with('feature-branch').and_return(false)
        end

        it 'returns ref not found error' do
          expect(result).to be_error
          expect(result.message).to eq('Ref does not exist in repository')
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end
      end

      context 'when repository does not exist' do
        before do
          allow(project).to receive(:repository_exists?).and_return(false)
        end

        it 'returns ref not found error' do
          expect(result).to be_error
          expect(result.message).to eq('Ref does not exist in repository')
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end
      end

      context 'when parameters are invalid' do
        let(:params) do
          {
            project: project,
            context_name: '',
            context_type: 'invalid',
            is_default: false,
            allow_untracked: false,
            current_user: user
          }
        end

        it 'returns validation error' do
          expect(result).to be_error
          expect(result.message).to eq('Invalid ref name or type specified')
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end
      end

      context 'when ref_type is tag' do
        let(:params) do
          {
            project: project,
            context_name: 'v1.0.0',
            context_type: :tag,
            is_default: false,
            allow_untracked: false,
            current_user: user
          }
        end

        before do
          allow(project.repository).to receive(:tag_exists?).with('v1.0.0').and_return(true)
          allow(project.repository).to receive(:branch_exists?).with('v1.0.0').and_return(false)
        end

        it 'validates tag existence' do
          expect(result).to be_error
          expect(result.message).to eq('Expected context to already exist for non-default branches')
        end

        context 'when tag does not exist' do
          before do
            allow(project.repository).to receive(:tag_exists?).with('v1.0.0').and_return(false)
          end

          it 'returns ref not found error' do
            expect(result).to be_error
            expect(result.message).to eq('Ref does not exist in repository')
          end
        end
      end
    end

    context 'when current_user is nil (internal usage)' do
      it 'bypasses permission checks and ref validation' do
        # This tests the existing behavior for internal usage
        expect(result).to be_success
      end
    end

    context 'when tracked context already exists' do
      let_it_be(:existing_context) do
        create(:security_project_tracked_context,
          :tracked,
          project: project,
          context_name: project.default_branch,
          context_type: :branch)
      end

      context 'when context is tracked' do
        it_behaves_like 'existing tracked context'
      end

      context 'when context is not tracked' do
        before_all do
          existing_context.untrack!
        end

        context 'when allow_untracked is false' do
          it 'returns an error' do
            expect(result).to be_error
            expect(result.message).to eq('Context is not tracked')
          end
        end

        context 'when allow_untracked is true' do
          let(:allow_untracked) { true }

          it_behaves_like 'existing tracked context'
        end
      end
    end

    context 'when tracked context does not exist' do
      context 'when is_default is true' do
        let(:is_default) { true }

        it_behaves_like 'context creation'

        context 'when tracked refs limit is exceeded' do
          let(:max_refs) { 1 }

          before do
            # The per-project ref cap only applies while org quota enforcement
            # is off; enforcement (when on) supersedes it with the org quota.
            stub_feature_flags(vac_increased_limit: false, security_tracked_context_quota_enforcement: false)
            stub_const('Security::ProjectTrackedContext::MAX_TRACKED_REFS_PER_PROJECT', max_refs)
            create(:security_project_tracked_context, :tracked, project: project)
          end

          it 'returns an error' do
            expect(result).to be_error
            expect(result.message).to include("cannot exceed #{max_refs} tracked refs per project")
          end

          it 'does not create a tracked context' do
            expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
          end
        end
      end

      context 'when is_default is false' do
        let(:is_default) { false }

        context 'when allow_untracked is false' do
          it 'returns an error' do
            expect(result).to be_error
            expect(result.message).to eq('Expected context to already exist for non-default branches')
          end

          it 'does not create a tracked context' do
            expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
          end
        end

        context 'when allow_untracked is true' do
          let(:allow_untracked) { true }

          it_behaves_like 'context creation'
        end
      end

      context 'when is_default is nil' do
        let(:is_default) { nil }

        it 'returns an error' do
          expect(result).to be_error
          expect(result.message).to eq('Expected context to already exist for non-default branches')
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end
      end
    end

    context 'when finding existing context by different attributes' do
      let_it_be(:branch_context) do
        create(:security_project_tracked_context,
          :tracked,
          project: project,
          context_name: 'develop',
          context_type: :branch)
      end

      let_it_be(:tag_context) do
        create(:security_project_tracked_context,
          :tracked,
          project: project,
          context_name: 'develop',
          context_type: :tag)
      end

      context 'when searching for a branch context' do
        let(:context_name) { 'develop' }
        let(:context_type) { :branch }

        it 'finds the branch context, not the tag context' do
          expect(result).to be_success
          expect(result.payload[:tracked_context]).to eq(branch_context)
        end
      end

      context 'when searching for a tag context' do
        let(:context_name) { 'develop' }
        let(:context_type) { :tag }

        it 'finds the tag context, not the branch context' do
          expect(result).to be_success
          expect(result.payload[:tracked_context]).to eq(tag_context)
        end
      end
    end

    context 'when multiple projects have contexts with the same name' do
      let_it_be(:other_project) { create(:project) }
      let_it_be(:other_project_context) do
        create(:security_project_tracked_context,
          :tracked,
          project: other_project,
          context_name: 'main',
          context_type: :branch)
      end

      it 'only finds contexts for the specified project' do
        expect(result).to be_success
        tracked_context = result.payload[:tracked_context]
        expect(tracked_context).to be_persisted
        expect(tracked_context.project).to eq(project)
        expect(tracked_context).not_to eq(other_project_context)
      end
    end

    context 'when ingesting for a default branch' do
      context 'when default context exists but the context_name differs' do
        let_it_be(:existing_context) do
          create(:security_project_tracked_context,
            :tracked,
            project: project,
            context_name: 'old_default',
            context_type: :branch,
            is_default: true
          )
        end

        let_it_be(:existing_context_2) do
          create(:security_project_tracked_context,
            :tracked,
            project: project,
            context_name: 'old_default_2',
            context_type: :branch,
            is_default: true
          )
        end

        it 'updates the latest default existing context', :aggregate_failures do
          expect { service.execute }
          .to not_change { Security::ProjectTrackedContext.count }
          .and not_change { existing_context.reload.context_name }

          existing_context_2.reload
          expect(existing_context_2.context_name).to eq(project.default_branch)
          expect(existing_context_2.context_type).to eq('branch')
          expect(existing_context_2.is_default).to be(true)
          expect(existing_context_2.project).to eq(project)
        end
      end
    end

    context 'when an existing context has drifted traversal_ids' do
      let(:drifted_traversal_ids) { [non_existing_record_id] }

      before do
        stub_feature_flags(sync_drifted_tracked_context_traversal_ids: true)
      end

      shared_examples 'enqueues a traversal_ids sync without writing inline' do
        it 'enqueues a traversal_ids sync for the project once, outside any transaction', :aggregate_failures do
          expect(Security::SyncTrackedContextTraversalIdsWorker).to receive(:perform_async).with(project.id).once do
            expect(SecApplicationRecord.inside_transaction?).to be(false)
          end

          expect { result }.not_to change { existing_context.reload.traversal_ids }
          expect(result).to be_success
        end
      end

      shared_examples 'does not enqueue a traversal_ids sync' do
        it 'does not enqueue a traversal_ids sync' do
          expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

          result
        end
      end

      context 'when the fast path finds an existing default context with the same name' do
        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context, :default,
            project: project,
            context_name: project.default_branch,
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'enqueues a traversal_ids sync without writing inline'

        context 'when traversal_ids are empty' do
          before do
            existing_context.update_column(:traversal_ids, [])
          end

          it_behaves_like 'enqueues a traversal_ids sync without writing inline'
        end

        context 'when traversal_ids are consistent' do
          before do
            existing_context.update_column(:traversal_ids, project.namespace.traversal_ids)
          end

          it_behaves_like 'does not enqueue a traversal_ids sync'
          it_behaves_like 'existing tracked context'
        end

        context 'when the in-memory project namespace is stale' do
          before do
            existing_context.update_column(:traversal_ids, project.namespace.traversal_ids)
            allow(project.namespace).to receive(:traversal_ids).and_return(drifted_traversal_ids)
          end

          it 'enqueues a sync without overwriting the traversal_ids of the context', :aggregate_failures do
            expect(Security::SyncTrackedContextTraversalIdsWorker).to receive(:perform_async).with(project.id)

            expect { result }.not_to change { existing_context.reload.traversal_ids }
            expect(result).to be_success
          end
        end

        context 'when called inside an open sec database transaction' do
          it 'does not enqueue a traversal_ids sync' do
            expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

            response = nil
            SecApplicationRecord.transaction { response = service.execute }

            expect(response).to be_success
          end
        end

        context 'when called inside an open main database transaction' do
          it 'does not enqueue a traversal_ids sync' do
            expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

            response = nil
            ApplicationRecord.transaction { response = service.execute }

            expect(response).to be_success
          end
        end

        context 'when sync_drifted_tracked_context_traversal_ids is disabled' do
          before do
            stub_feature_flags(sync_drifted_tracked_context_traversal_ids: false)
          end

          it_behaves_like 'does not enqueue a traversal_ids sync'
        end

        context 'when enqueueing the sync fails' do
          let(:error) { StandardError.new('Redis unavailable') }

          before do
            allow(Security::SyncTrackedContextTraversalIdsWorker).to receive(:perform_async).and_raise(error)
            allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
          end

          it 'tracks the exception and returns the existing context', :aggregate_failures do
            expect(result).to be_success
            expect(result.payload[:tracked_context]).to eq(existing_context)
            expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
              .with(error, project_id: project.id)
          end
        end
      end

      context 'when the context is not tracked and allow_untracked is false' do
        let(:context_name) { 'feature-branch' }
        let(:is_default) { false }

        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context,
            project: project,
            context_name: 'feature-branch',
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'does not enqueue a traversal_ids sync'

        it 'returns an error' do
          expect(result).to be_error
          expect(result.message).to eq('Context is not tracked')
        end
      end

      context 'when the context is not tracked and allow_untracked is true' do
        let(:context_name) { 'feature-branch' }
        let(:is_default) { false }
        let(:allow_untracked) { true }

        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context, :untracked,
            project: project,
            context_name: 'feature-branch',
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'enqueues a traversal_ids sync without writing inline'
      end

      context 'when the existing context is not the default' do
        let(:context_name) { 'feature-branch' }
        let(:is_default) { false }

        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context, :tracked,
            project: project,
            context_name: 'feature-branch',
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'enqueues a traversal_ids sync without writing inline'
      end

      context 'when the existing context is a tag' do
        let(:context_name) { 'v1.0.0' }
        let(:context_type) { :tag }
        let(:is_default) { false }

        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context, :tracked, :tag,
            project: project,
            context_name: 'v1.0.0',
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'enqueues a traversal_ids sync without writing inline'
      end

      context 'when renaming an existing default context' do
        let_it_be_with_reload(:existing_context) do
          create(:security_project_tracked_context, :default,
            project: project,
            context_name: 'old_default',
            traversal_ids: [non_existing_record_id])
        end

        it_behaves_like 'enqueues a traversal_ids sync without writing inline'

        it 'renames the context' do
          expect { result }.to change { existing_context.reload.context_name }.to(project.default_branch)
        end

        context 'when called inside an open sec database transaction' do
          it 'renames the context without enqueueing a traversal_ids sync', :aggregate_failures do
            expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

            response = nil
            SecApplicationRecord.transaction { response = service.execute }

            expect(response).to be_success
            expect(existing_context.reload.context_name).to eq(project.default_branch)
          end
        end

        context 'when traversal_ids are consistent' do
          before do
            existing_context.update_column(:traversal_ids, project.namespace.traversal_ids)
          end

          it_behaves_like 'does not enqueue a traversal_ids sync'
        end

        context 'when the lock is already being held' do
          before do
            allow(service).to receive(:obtain_lock).and_return(false)
          end

          it_behaves_like 'does not enqueue a traversal_ids sync'

          it 'returns a busy error without renaming the context', :aggregate_failures do
            expect { result }.not_to change { existing_context.reload.context_name }
            expect(result.reason).to eq(:tracked_context_busy)
          end
        end

        context 'when sync_drifted_tracked_context_traversal_ids is disabled' do
          before do
            stub_feature_flags(sync_drifted_tracked_context_traversal_ids: false)
          end

          it_behaves_like 'does not enqueue a traversal_ids sync'

          it 'renames the context' do
            expect { result }.to change { existing_context.reload.context_name }.to(project.default_branch)
          end
        end
      end

      context 'when no context exists and the created context looks drifted' do
        before do
          allow_next_instance_of(Security::ProjectTrackedContext) do |context|
            context.traversal_ids = drifted_traversal_ids
          end
        end

        it 'creates the context with the drifted traversal_ids', :aggregate_failures do
          expect { result }.to change { Security::ProjectTrackedContext.where(project: project).count }.by(1)
          expect(result.payload[:tracked_context].reload.traversal_ids).to eq(drifted_traversal_ids)
        end

        it_behaves_like 'does not enqueue a traversal_ids sync'
      end

      context 'when a previous run marked a drift but raised before enqueueing it' do
        before_all do
          create(:security_project_tracked_context, :default,
            project: project,
            context_name: project.default_branch,
            traversal_ids: project.namespace.traversal_ids)
        end

        it 'does not enqueue a traversal_ids sync from the stale mark' do
          service.instance_variable_set(:@traversal_ids_sync_pending, true)

          expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

          expect(result).to be_success
        end
      end

      context 'when another process created a drifted context before the locked re-check' do
        it 'enqueues a traversal_ids sync for the project once, after the lock transaction', :aggregate_failures do
          created_context = nil

          allow(service).to receive(:obtain_lock).and_wrap_original do |method|
            created_context = create(:security_project_tracked_context, :default,
              project: project,
              context_name: project.default_branch,
              traversal_ids: drifted_traversal_ids)

            method.call
          end

          expect(Security::SyncTrackedContextTraversalIdsWorker).to receive(:perform_async).with(project.id).once do
            expect(SecApplicationRecord.inside_transaction?).to be(false)
          end

          expect(result).to be_success
          expect(result.payload[:tracked_context]).to eq(created_context)
          expect(created_context.reload.traversal_ids).to eq(drifted_traversal_ids)
        end
      end
    end
  end

  describe 'advisory locking' do
    context 'when creation raises an unrelated uniqueness error' do
      it 'does not hide the database error' do
        failure = ActiveRecord::RecordNotUnique.new('Unrelated unique constraint')
        allow(service).to receive(:create_context).and_raise(failure)

        expect { service.execute }.to raise_error(failure)
      end
    end

    context 'when renaming fails an unrelated validation' do
      it 'does not hide the validation error' do
        existing_default = create(:security_project_tracked_context, :default,
          project: project, context_name: 'old-default')
        existing_default.errors.add(:base, 'Unrelated validation failure')
        failure = ActiveRecord::RecordInvalid.new(existing_default)
        allow(service).to receive(:updated_default_branch_context).and_raise(failure)

        expect { service.execute }.to raise_error(failure)
      end
    end

    context 'when no tracked context exists yet' do
      context 'when the lock is not being held' do
        it 'runs the critical section of the code in lock, using the default-scoped key' do
          expect(Security::ProjectTrackedContext.connection).to receive(:select_value)
            .with("SELECT pg_try_advisory_xact_lock(" \
              "hashtextextended('security:project_tracked_contexts:#{project.id}:default', 0))")
            .and_call_original

          service.execute
        end

        it 'performs the in-lock re-check on the primary' do
          session = ::Gitlab::Database::LoadBalancing::SessionMap.current(::SecApplicationRecord.load_balancer)

          expect(session).to receive(:use_primary).and_call_original

          service.execute
        end
      end

      context 'when the requested context is not the default branch' do
        let(:params) do
          {
            project: project,
            context_name: 'feature-branch',
            context_type: :branch,
            is_default: false,
            allow_untracked: true
          }
        end

        before do
          allow(project.repository).to receive(:branch_exists?).with('feature-branch').and_return(true)
        end

        it 'uses a ref-scoped lock key' do
          expect(Security::ProjectTrackedContext.connection).to receive(:select_value)
            .with("SELECT pg_try_advisory_xact_lock(" \
              "hashtextextended('security:project_tracked_contexts:#{project.id}:branch:feature-branch', 0))")
            .and_call_original

          service.execute
        end
      end

      context 'when the lock is already being held' do
        before do
          allow(service).to receive(:obtain_lock).and_return(false)
        end

        it 'does not create a tracked context' do
          expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        end

        it 'returns an error response' do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:tracked_context_busy)
          expect(result.message).to eq(_('Tracked context is being updated. Please try again.'))
        end
      end
    end

    context 'when a tracked context already exists' do
      let_it_be(:existing_context) do
        create(:security_project_tracked_context,
          :tracked,
          project: project,
          context_name: project.default_branch,
          context_type: :branch)
      end

      it 'does not request an advisory lock' do
        expect(service).not_to receive(:obtain_lock)

        service.execute
      end
    end

    context 'when called inside an open database transaction' do
      it 'creates the context while holding an advisory lock' do
        expect(service).to receive(:obtain_lock).and_call_original

        result = nil

        expect do
          SecApplicationRecord.transaction { result = service.execute }
        end.to change { Security::ProjectTrackedContext.count }.by(1)

        expect(result).to be_success
        expect(result.payload[:tracked_context]).to be_persisted
      end
    end

    context 'when the race window closes inside the lock' do
      it 'returns the record created by the concurrent request instead of a duplicate' do
        created_context = nil

        # Simulate another process creating the context after this process's fast-path
        # check found nothing, but before this process's in-lock re-check runs.
        allow(service).to receive(:obtain_lock).and_wrap_original do |method|
          created_context = create(:security_project_tracked_context,
            :tracked,
            project: project,
            context_name: project.default_branch,
            context_type: :branch)

          method.call
        end

        result = nil

        expect { result = service.execute }.to change { Security::ProjectTrackedContext.count }.by(1)

        expect(result).to be_success
        expect(result.payload[:tracked_context]).to eq(created_context)
      end
    end

    context 'when a differently named default context is created inside the lock' do
      it 'renames the existing default context instead of creating a second one' do
        existing_default = nil

        allow(service).to receive(:obtain_lock).and_wrap_original do |method|
          existing_default = create(:security_project_tracked_context, :default,
            project: project,
            context_name: "stale-#{project.default_branch}")

          method.call
        end

        result = nil

        expect { result = service.execute }.to change { Security::ProjectTrackedContext.count }.by(1)

        expect(result).to be_success
        expect(result.payload[:tracked_context]).to eq(existing_default)
        expect(existing_default.reload.context_name).to eq(project.default_branch)
      end
    end

    context 'when the branch type is provided as a string' do
      let(:context_type) { 'branch' }

      it 'reuses the existing default instead of creating another one', :aggregate_failures do
        existing_default = create(:security_project_tracked_context, :default,
          project: project, context_name: 'old-default')

        expect { service.execute }.not_to change { Security::ProjectTrackedContext.count }
        expect(existing_default.reload.context_name).to eq(project.default_branch)
      end
    end

    context 'when the repository has no default branch yet' do
      let(:context_name) { 'main' }

      before do
        allow(project).to receive_messages(default_branch: nil, default_branch_or_main: 'main')
      end

      it 'renames the existing default using the fallback name', :aggregate_failures do
        existing_default = create(:security_project_tracked_context, :default,
          project: project, context_name: 'old-default')

        expect(service.execute).to be_success
        expect(existing_default.reload.context_name).to eq('main')
      end
    end
  end

  describe '#ref_exists_in_repository?' do
    subject(:ref_exists) { service.send(:ref_exists_in_repository?) }

    context 'when repository does not exist' do
      before do
        allow(project).to receive(:repository_exists?).and_return(false)
      end

      it 'returns false' do
        expect(ref_exists).to be false
      end
    end

    context 'when repository exists' do
      before do
        allow(project).to receive(:repository_exists?).and_return(true)
      end

      context 'when context_type is branch' do
        let(:context_type) { :branch }

        it 'checks branch existence' do
          expect(project.repository).to receive(:branch_exists?).with(context_name)
          ref_exists
        end
      end

      context 'when context_type is tag' do
        let(:context_type) { :tag }

        it 'checks tag existence' do
          expect(project.repository).to receive(:tag_exists?).with(context_name)
          ref_exists
        end
      end

      context 'when context_type is invalid' do
        let(:context_type) { :invalid_type }

        it 'returns false for unknown context types' do
          expect(ref_exists).to be false
        end
      end
    end
  end
end
