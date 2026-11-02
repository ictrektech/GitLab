# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::RakeTask::SemanticSearchDevSetup, :silence_stdout, feature_category: :global_search do
  subject(:setup_task) { described_class.new }

  before do
    stub_rails_env('development')
    stub_env('GITLAB_SIMULATE_SAAS', '1')
    stub_env('DEVELOPMENT_AI_GATEWAY_URL', 'http://gdk.test:5052')
  end

  describe '.new' do
    it 'can be created in the development environment' do
      expect(described_class.new).to be_a(described_class)
    end

    context 'when not in the development environment' do
      before do
        stub_rails_env('production')
      end

      it 'raises an error' do
        expect { described_class.new }
          .to raise_error(described_class::Error, 'This task can only run in the development environment.')
      end
    end
  end

  describe '.setup' do
    it 'delegates to a new instance' do
      expect_next_instance_of(described_class) do |instance|
        expect(instance).to receive(:setup)
      end

      described_class.setup
    end
  end

  describe '.index_project' do
    it 'delegates to a new instance' do
      expect_next_instance_of(described_class) do |instance|
        expect(instance).to receive(:index_project).with(project_path: 'group/project')
      end

      described_class.index_project(project_path: 'group/project')
    end
  end

  describe '#setup' do
    def adapter_with_ping(result)
      raw_client = instance_double(::Elasticsearch::Client, ping: result)
      client = instance_double(ActiveContext::Databases::Elasticsearch::Client, client: raw_client)

      instance_double(ActiveContext::Databases::Elasticsearch::Adapter, client: client)
    end

    let(:migration_worker) { instance_double(Ai::ActiveContext::MigrationWorker, perform: true) }
    let(:embedding_model) { { model_ref: 'text_embedding_005_vertex', field: 'embeddings_v1' } }
    let(:collection) do
      instance_double(
        Ai::ActiveContext::Collection,
        current_indexing_embedding_model: embedding_model,
        search_embedding_model: embedding_model
      )
    end

    let(:cluster_responds) { true }
    let(:failed_migrations) { instance_double(ActiveRecord::Relation, exists?: false, pluck: []) }
    let(:processable_migrations) { instance_double(ActiveRecord::Relation, exists?: false) }
    let(:migrations) do
      class_double(Ai::ActiveContext::Migration, failed: failed_migrations, processable: processable_migrations)
    end

    before do
      allow(::Gitlab::AiGateway).to receive(:has_self_hosted_ai_gateway?).and_return(false)
      allow(Ai::ActiveContext::MigrationWorker).to receive(:new).and_return(migration_worker)
      allow(Ai::ActiveContext::Collections::Code).to receive(:collection_record).and_return(collection)
      allow(Ai::ActiveContext::ConnectionService).to receive(:connect_to_advanced_search_cluster) do
        create(:ai_active_context_connection)
      end

      allow_next_found_instance_of(Ai::ActiveContext::Connection) do |connection|
        allow(connection).to receive_messages(adapter: adapter_with_ping(cluster_responds), migrations: migrations)
      end
    end

    context 'when GITLAB_SIMULATE_SAAS is not set' do
      before do
        stub_env('GITLAB_SIMULATE_SAAS', nil)
      end

      it 'raises an error without making any changes', :aggregate_failures do
        expect { setup_task.setup }
          .to raise_error(
            described_class::Error,
            'Development setup is only supported in SaaS mode (GITLAB_SIMULATE_SAAS=1).'
          )
          .and not_change { Ai::ActiveContext::Connection.count }
        expect(migration_worker).not_to have_received(:perform)
      end
    end

    shared_examples 'runs the setup steps on the active connection' do
      it 'runs the migration worker until no migrations are processable' do
        allow(processable_migrations).to receive(:exists?).and_return(true, false)

        expect(migration_worker).to receive(:perform).twice

        setup_task.setup
      end

      it 'enables the feature flags' do
        stub_feature_flags(semantic_code_search_saas_ga: false)

        setup_task.setup

        expect(Feature.enabled?(:semantic_code_search_saas_ga, :instance)).to be(true)
      end

      context 'when a migration fails' do
        before do
          allow(failed_migrations).to receive_messages(exists?: true, pluck: ['20250101000001'])
        end

        it 'raises an error with the failed version' do
          expect { setup_task.setup }
            .to raise_error(described_class::Error, 'Migrations failed: 20250101000001')
        end
      end

      context 'when migrations do not complete' do
        before do
          allow(processable_migrations).to receive(:exists?).and_return(true)
        end

        it 'raises an error after the maximum number of runs' do
          expect(migration_worker).to receive(:perform).exactly(described_class::MAX_MIGRATION_RUNS).times
          expect { setup_task.setup }.to raise_error(described_class::Error, /did not complete/)
        end
      end

      context 'when the code collection has no current indexing embedding model' do
        let(:collection) do
          instance_double(
            Ai::ActiveContext::Collection,
            current_indexing_embedding_model: nil,
            search_embedding_model: embedding_model
          )
        end

        it 'raises an error' do
          expect { setup_task.setup }.to raise_error(
            described_class::Error,
            'The code collection has no current_indexing_embedding_model after running migrations.'
          )
        end
      end

      context 'when the code collection has no search embedding model' do
        let(:collection) do
          instance_double(
            Ai::ActiveContext::Collection,
            current_indexing_embedding_model: embedding_model,
            search_embedding_model: nil
          )
        end

        it 'raises an error' do
          expect { setup_task.setup }.to raise_error(
            described_class::Error, 'The code collection has no search_embedding_model after running migrations.'
          )
        end
      end

      context 'when the code collection does not exist' do
        let(:collection) { nil }

        it 'raises an error naming both embedding models' do
          expect { setup_task.setup }.to raise_error(
            described_class::Error,
            'The code collection has no current_indexing_embedding_model or search_embedding_model ' \
              'after running migrations.'
          )
        end
      end
    end

    context 'when a self-hosted AI Gateway URL is set' do
      let(:application_settings) { ::Gitlab::CurrentSettings.current_application_settings }

      before do
        allow(::Gitlab::AiGateway).to receive(:has_self_hosted_ai_gateway?).and_call_original
        application_settings.update!(ai_gateway_url: 'https://aigw.example.com')
      end

      it 'clears the AI Gateway URL and warns about it', :aggregate_failures do
        expect { setup_task.setup }
          .to output(%r{Self-hosted AI Gateway URL is set \(https://aigw.example.com\)}).to_stdout

        expect(application_settings.reload.ai_gateway_url).to be_nil
      end

      context 'when the AI Gateway URL cannot be cleared' do
        before do
          allow_next_instance_of(ApplicationSettings::UpdateService) do |service|
            allow(service).to receive(:execute) do
              Gitlab::CurrentSettings.current_application_settings.errors.add(:base, 'Settings are invalid')
              false
            end
          end
        end

        it 'raises an error without running the migrations', :aggregate_failures do
          expect { setup_task.setup }.to raise_error(
            described_class::Error, 'Could not clear the self-hosted AI Gateway URL: Settings are invalid'
          )
          expect(migration_worker).not_to have_received(:perform)
          expect(application_settings.reload.ai_gateway_url).to eq('https://aigw.example.com')
        end
      end
    end

    context 'when no self-hosted AI Gateway URL is set' do
      it 'does not update the application settings and logs that the URL is not set' do
        expect(ApplicationSettings::UpdateService).not_to receive(:new)

        expect { setup_task.setup }
          .to output(/Self-hosted AI Gateway URL:\t+not set \(expected\)/)
          .to_stdout
      end
    end

    context 'when no connection is active' do
      it 'connects to the advanced search cluster' do
        expect(Ai::ActiveContext::ConnectionService).to receive(:connect_to_advanced_search_cluster)

        expect { setup_task.setup }.to change { Ai::ActiveContext::Connection.count }.by(1)
      end

      it_behaves_like 'runs the setup steps on the active connection'

      context 'when the advanced search cluster cannot be reached' do
        before do
          allow(Ai::ActiveContext::ConnectionService).to receive(:connect_to_advanced_search_cluster)
            .and_raise(Ai::ActiveContext::ConnectionService::ConnectionError, 'Connection invalid')
        end

        it 'raises an error' do
          expect { setup_task.setup }
            .to raise_error(described_class::Error, /Could not connect to the advanced search cluster/)
        end
      end

      context 'when the new connection does not respond' do
        let(:cluster_responds) { false }

        before do
          allow(Ai::ActiveContext::ConnectionService).to receive(:connect_to_advanced_search_cluster) do
            create(:ai_active_context_connection, :elasticsearch)
          end
        end

        it 'raises an error and rolls back the new connection', :aggregate_failures do
          expect { setup_task.setup }
            .to raise_error(described_class::Error, /The cluster did not respond/)
            .and not_change { Ai::ActiveContext::Connection.count }
        end
      end
    end

    context 'when a connection is already active' do
      before do
        create(:ai_active_context_connection, :elasticsearch)
      end

      it 'reuses the active connection' do
        expect(Ai::ActiveContext::ConnectionService).not_to receive(:connect_to_advanced_search_cluster)

        setup_task.setup
      end

      it_behaves_like 'runs the setup steps on the active connection'

      context 'when the cluster does not respond' do
        let(:cluster_responds) { false }

        it 'raises an error' do
          expect { setup_task.setup }.to raise_error(described_class::Error, /The cluster did not respond/)
        end
      end
    end
  end

  describe '#index_project' do
    subject(:index_project) { setup_task.index_project }

    context 'when GITLAB_SIMULATE_SAAS is 0' do
      before do
        stub_env('GITLAB_SIMULATE_SAAS', '0')
      end

      it 'raises an error' do
        expect { index_project }.to raise_error(
          described_class::Error,
          'Development setup is only supported in SaaS mode (GITLAB_SIMULATE_SAAS=1).'
        )
      end
    end

    context 'when DEVELOPMENT_AI_GATEWAY_URL is not set' do
      before do
        stub_env('DEVELOPMENT_AI_GATEWAY_URL', nil)
      end

      it 'raises an error' do
        expect { index_project }.to raise_error(
          described_class::Error,
          'DEVELOPMENT_AI_GATEWAY_URL must be set so embeddings requests reach the local AI Gateway.'
        )
      end
    end

    context 'when indexing is not available' do
      before do
        allow(Ai::ActiveContext::Collections::Code).to receive(:indexing?).and_return(false)
      end

      it 'raises an error' do
        expect { index_project }
          .to raise_error(described_class::Error, /Run gitlab:semantic_search:setup first/)
      end
    end

    context 'when queues are not empty' do
      before do
        allow(Ai::ActiveContext::Collections::Code).to receive(:indexing?).and_return(true)
        allow(ActiveContext::Queues).to receive(:queue_counts).and_return([
          { queue_name: 'Ai::ActiveContext::Queues::Code', shard: 0, count: 2 },
          { queue_name: 'Ai::ActiveContext::Queues::Code', shard: 1, count: 3 },
          { queue_name: 'ActiveContext::RetryQueue', shard: 0, count: 0 }
        ])
        allow(ActiveContext::DeadQueue).to receive(:queue_size).and_return(3)
      end

      it 'raises an error with the total size of each non-empty queue without indexing' do
        expect { index_project }
          .to raise_error(
            described_class::Error,
            'All ActiveContext queues must be empty before indexing. ' \
              'Non-empty queues: Ai::ActiveContext::Queues::Code: 5, ActiveContext::DeadQueue: 3'
          )
          .and not_change { Ai::ActiveContext::Code::Repository.count }
      end
    end

    context 'when all prerequisites are satisfied' do
      let_it_be(:connection) { create(:ai_active_context_connection) }

      let_it_be(:group) { create(:group, path: 'gitlab-duo') }
      let_it_be(:project) { create(:project, group: group, path: 'ai-gateway') }

      let(:index_worker) { instance_double(Ai::ActiveContext::Code::RepositoryIndexWorker) }
      let(:mark_ready_worker) { instance_double(Ai::ActiveContext::Code::MarkRepositoryAsReadyEventWorker) }
      let(:repository) { connection.repositories.find_by(project_id: project.id) }

      before do
        allow(Ai::ActiveContext::Collections::Code).to receive(:indexing?).and_return(true)
        allow(ActiveContext::Queues).to receive_messages(queue_counts: [], retry_chain: [])
        allow(ActiveContext::DeadQueue).to receive(:queue_size).and_return(0)
        allow(ActiveContext).to receive(:execute_all_queues!)
        allow(Ai::ActiveContext::Queues::Code).to receive(:queue_size).and_return(0)

        allow(Ai::ActiveContext::Code::RepositoryIndexWorker).to receive(:new).and_return(index_worker)
        allow(index_worker).to receive(:perform) do |id|
          Ai::ActiveContext::Code::Repository.find_by_id(id).embedding_indexing_in_progress!
        end

        allow(Ai::ActiveContext::Code::MarkRepositoryAsReadyEventWorker).to receive(:new).and_return(mark_ready_worker)
        allow(mark_ready_worker).to receive(:handle_event) do
          Ai::ActiveContext::Code::Repository.embedding_indexing_in_progress.update_all(state: :ready)
        end
      end

      it 'indexes the project, generates its embeddings, and marks the repository as ready', :aggregate_failures do
        logger = instance_double(Logger, info: nil, warn: nil)
        allow(setup_task).to receive(:logger).and_return(logger)
        allow(Ai::ActiveContext::Queues::Code).to receive(:queue_size).and_return(8, 5, 0)

        expect(index_worker).to receive(:perform).ordered
        expect(ActiveContext).to receive(:execute_all_queues!).twice.ordered
        expect(mark_ready_worker).to receive(:handle_event).ordered

        expect { index_project }
          .to change { Ai::ActiveContext::Code::Repository.find_by(project_id: project.id)&.state }
          .from(nil).to('ready')

        enabled_namespace = Ai::ActiveContext::Code::EnabledNamespace.find_enabled_namespace(connection, group)
        expect(enabled_namespace).to be_ready
        expect(repository.enabled_namespace_id).to eq(enabled_namespace.id)

        expect(logger).to have_received(:info).with(/Initial queue size:\t+8/)
        expect(logger).to have_received(:info)
          .with(/Processed embeddings:\t+processed: 3, queue after: 5 \(elapsed: .+s\)/)
        expect(logger).to have_received(:info)
          .with(/Processed embeddings:\t+processed: 5, queue after: 0 \(elapsed: .+s\)/)
        expect(logger).to have_received(:info).with(/Embeddings generated in:\t+.+s/)
        expect(logger).to have_received(:info).with(/Indexing complete: repository is ready/)
      end

      context 'when the enabled namespace and repository already exist' do
        let!(:enabled_namespace) do
          create(:ai_active_context_code_enabled_namespace, namespace: group, active_context_connection: connection)
        end

        let!(:existing_repository) do
          create(:ai_active_context_code_repository, :ready, project: project, enabled_namespace: enabled_namespace)
        end

        it 'marks the enabled namespace as ready', :aggregate_failures do
          expect { index_project }.to output(/\(id=#{enabled_namespace.id}, marked as ready\)/).to_stdout

          expect(enabled_namespace.reload).to be_ready
        end

        it 'resets the repository to pending before indexing', :aggregate_failures do
          expect(index_worker).to receive(:perform).with(existing_repository.id) do |id|
            expect(Ai::ActiveContext::Code::Repository.find_by_id(id)).to be_pending

            Ai::ActiveContext::Code::Repository.find_by_id(id).embedding_indexing_in_progress!
          end

          expect { index_project }.to output(/id=#{existing_repository.id} \(reset\)/).to_stdout
        end

        context 'when the enabled namespace is already ready' do
          before do
            enabled_namespace.ready!
          end

          it 'logs that it is already ready' do
            expect { index_project }.to output(/\(id=#{enabled_namespace.id}, already ready\)/).to_stdout
          end
        end
      end

      context 'when the code queue stops shrinking' do
        before do
          allow(Ai::ActiveContext::Queues::Code).to receive(:queue_size).and_return(5)
          allow(setup_task).to receive(:sleep)
        end

        it 'raises an error after the maximum number of stalled runs', :aggregate_failures do
          expect { index_project }.to raise_error(
            described_class::Error,
            "The code queue did not shrink in #{described_class::MAX_STALLED_QUEUE_RUNS} runs (size: 5). " \
              'Check log/active_context.log.'
          )
          expect(ActiveContext).to have_received(:execute_all_queues!)
            .exactly(described_class::MAX_STALLED_QUEUE_RUNS).times
          expect(setup_task).to have_received(:sleep)
            .with(described_class::STALLED_QUEUE_SLEEP_SECONDS)
            .exactly(described_class::MAX_STALLED_QUEUE_RUNS - 1).times
        end
      end

      context 'when repository indexing fails' do
        before do
          allow(index_worker).to receive(:perform) do |id|
            Ai::ActiveContext::Code::Repository.find_by_id(id).update!(state: :pending_retry, last_error: 'boom')
          end
        end

        it 'raises an error with the repository state and last error' do
          expect { index_project }
            .to raise_error(described_class::Error, 'Repository indexing failed with state pending_retry: boom')
        end
      end

      context 'when some embeddings fail' do
        before do
          allow(Ai::ActiveContext::Queues::Code).to receive(:queue_size).and_return(8, 5)
          allow(ActiveContext::Queues).to receive(:retry_chain)
            .and_return([class_double(ActiveContext::RetryQueue, queue_size: 2)])
        end

        it 'raises an error after the first run', :aggregate_failures do
          expect { index_project }.to raise_error(
            described_class::Error,
            'Embeddings generation failed for 2 documents, which were moved to the retry queues. ' \
              'Check log/active_context.log.'
          )
          expect(ActiveContext).to have_received(:execute_all_queues!).once
        end
      end

      context 'when the repository is not marked as ready' do
        before do
          allow(mark_ready_worker).to receive(:handle_event)
        end

        it 'raises an error' do
          expect { index_project }.to raise_error(
            described_class::Error, 'Repository was not marked as ready, its state is embedding_indexing_in_progress'
          )
        end
      end

      context 'when the default project does not exist' do
        before do
          Project.find(project.id).destroy!
          Group.find(group.id).destroy!
        end

        it 'raises an error' do
          expect { index_project }
            .to raise_error(described_class::Error, "Project not found: #{described_class::DEFAULT_PROJECT_PATH}")
        end
      end

      context 'when the project is set' do
        subject(:index_project) { setup_task.index_project(project_path: other_project.full_path) }

        let_it_be(:other_project) { create(:project, group: create(:group)) }

        it 'indexes the given project', :aggregate_failures do
          index_project

          expect(connection.repositories.find_by(project_id: other_project.id)).to be_ready
          expect(repository).to be_nil
        end

        context 'when the project does not exist' do
          subject(:index_project) { setup_task.index_project(project_path: 'non/existent') }

          it 'raises an error' do
            expect { index_project }.to raise_error(described_class::Error, 'Project not found: non/existent')
          end
        end

        context 'when the project is in a user namespace' do
          let_it_be(:other_project) { create(:project) }

          it 'raises a validation error' do
            expect { index_project }.to raise_error(ActiveRecord::RecordInvalid, /must be a root group/)
          end
        end
      end
    end
  end
end
