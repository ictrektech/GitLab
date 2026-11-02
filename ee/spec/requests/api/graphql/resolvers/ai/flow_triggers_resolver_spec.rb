# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::FlowTriggersResolver, :with_current_organization, feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:reporter) { create(:user) }
  let_it_be(:project) do
    create(:project, :in_group, maintainers: maintainer, developers: developer, reporters: reporter)
  end

  let_it_be(:triggers) { create_list(:ai_flow_trigger, 3, project: project) }
  let_it_be(:other_project) { create(:project, maintainers: maintainer) }
  let_it_be(:other_trigger) { create(:ai_flow_trigger, project: other_project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:nodes) { graphql_data_at(:project, :ai_flow_triggers, :nodes) }
  let(:current_user) { maintainer }
  let(:args) { '' }

  let(:query) do
    <<~GQL
      {
        project(fullPath: "#{project.full_path}") {
          aiFlowTriggers#{args} {
            nodes {
              id
            }
          }
        }
      }
    GQL
  end

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(current_organization).update!(duo_core_features_enabled: true)
    stub_ee_application_setting(duo_features_enabled: true)
  end

  context 'when developer' do
    let(:current_user) { developer }

    it 'returns all flow triggers for project' do
      post_graphql(query, current_user: current_user)

      expect(nodes).to match_array(triggers.map { |trigger| a_graphql_entity_for(trigger) })
    end
  end

  context 'when reporter' do
    let(:current_user) { reporter }

    it 'returns no flow triggers' do
      post_graphql(query, current_user: current_user)

      expect(nodes).to be_empty
    end
  end

  it 'returns all flow triggers for project' do
    post_graphql(query, current_user: current_user)

    expect(nodes).to match_array(
      triggers.map { |trigger| a_graphql_entity_for(trigger) }
    )
  end

  context 'with an inactive trigger' do
    let_it_be(:inactive_trigger) { create(:ai_flow_trigger, :inactive, project: project) }

    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{project.full_path}") {
            aiFlowTriggers {
              nodes {
                id
                active
              }
            }
          }
        }
      GQL
    end

    it 'still lists the inactive trigger and exposes the active field' do
      post_graphql(query, current_user: current_user)

      expect(nodes).to include(a_graphql_entity_for(inactive_trigger, active: false))
      expect(nodes).to include(a_graphql_entity_for(triggers.first, active: true))
    end
  end

  describe 'configUrl field' do
    let_it_be(:project_with_repo) { create(:project, :in_group, :repository, maintainers: maintainer) }

    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{project_with_repo.full_path}") {
            aiFlowTriggers {
              nodes {
                configUrl
              }
            }
          }
        }
      GQL
    end

    context 'when the trigger has a config_path and the project has a repository' do
      let_it_be(:trigger_with_config) do
        create(:ai_flow_trigger, project: project_with_repo, config_path: 'path/to/config.yml')
      end

      it 'returns the blob URL for the config file' do
        post_graphql(query, current_user: current_user)

        config_url = graphql_data_at(:project, :ai_flow_triggers, :nodes).first['configUrl']
        expect(config_url).to include(project_with_repo.default_branch, 'path/to/config.yml')
      end
    end

    context 'when config_path is nil (catalog mode trigger)' do
      let_it_be(:catalog_item) { create(:ai_catalog_flow) }
      let_it_be(:item_consumer) do
        create(:ai_catalog_item_consumer, :child_item_consumer, project: project_with_repo, item: catalog_item)
      end

      let_it_be(:trigger_catalog_mode) do
        create(
          :ai_flow_trigger, :for_catalog_consumer, project: project_with_repo, ai_catalog_item_consumer: item_consumer
        )
      end

      it 'returns nil' do
        post_graphql(query, current_user: current_user)

        config_url = graphql_data_at(:project, :ai_flow_triggers, :nodes).first['configUrl']
        expect(config_url).to be_nil
      end
    end

    # Empty string config_path can exist in legacy DB records but fails model validation,
    # so config_path must be stubbed rather than persisted directly.
    context 'when config_path is an empty string' do
      let_it_be(:trigger_empty_path) { create(:ai_flow_trigger, project: project_with_repo) }

      before do
        allow_next_found_instance_of(Ai::FlowTrigger) do |trigger|
          allow(trigger).to receive(:config_path).and_return('')
        end
      end

      it 'returns nil' do
        post_graphql(query, current_user: current_user)

        config_url = graphql_data_at(:project, :ai_flow_triggers, :nodes).first['configUrl']
        expect(config_url).to be_nil
      end
    end

    context 'when the project has no repository' do
      let_it_be(:empty_project) { create(:project_empty_repo, maintainers: maintainer) }
      let_it_be(:trigger_no_repo) do
        create(:ai_flow_trigger, project: empty_project, config_path: 'path/to/config.yml')
      end

      let(:query) do
        <<~GQL
          {
            project(fullPath: "#{empty_project.full_path}") {
              aiFlowTriggers {
                nodes {
                  configUrl
                }
              }
            }
          }
        GQL
      end

      it 'returns nil' do
        post_graphql(query, current_user: current_user)

        config_url = graphql_data_at(:project, :ai_flow_triggers, :nodes).first['configUrl']
        expect(config_url).to be_nil
      end
    end
  end

  describe 'N+1 queries' do
    let_it_be(:group_project) { create(:project, :in_group, maintainers: maintainer) }

    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{group_project.full_path}") {
            aiFlowTriggers {
              nodes {
                id
                configUrl
                precondition
                project { id }
                user { id }
                aiCatalogItemConsumer { id item { id name } }
                flowSchedules { nodes { id } }
              }
            }
          }
        }
      GQL
    end

    def create_triggers
      [
        create(:ai_flow_trigger, project: group_project),
        create(:ai_flow_trigger, :for_catalog_consumer, project: group_project),
        create(:ai_flow_trigger, :autonomous, project: group_project)
      ].each { |trigger| create(:ai_flow_schedule, flow_trigger: trigger) }
    end

    it 'does not run more queries for more triggers' do
      create_triggers
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: current_user)
      end

      create_triggers

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
      expect(graphql_data_at(:project, :ai_flow_triggers, :nodes).size).to eq(6)
    end
  end

  context 'with filter and sort arguments' do
    let_it_be(:sorted_project) { create(:project, :in_group, maintainers: maintainer) }
    let_it_be(:victor) do
      create(:ai_flow_trigger, :autonomous, project: sorted_project, description: 'victor automation')
    end

    let_it_be(:whiskey) do
      create(:ai_flow_trigger, project: sorted_project, description: 'whiskey automation',
        event_types: [::Ai::FlowTrigger::EVENT_TYPES[:assign]])
    end

    let_it_be(:xray) { create(:ai_flow_trigger, project: sorted_project, description: 'xray automation') }
    let_it_be(:yankee) { create(:ai_flow_trigger, project: sorted_project, description: 'Yankee automation') }
    let_it_be(:zulu) { create(:ai_flow_trigger, :inactive, project: sorted_project, description: 'zulu automation') }

    let(:filter_args) do
      { kind: :EVENT, active: true, event_type: :MENTION, search: 'automation', sort: :NAME_DESC }
    end

    let(:query) do
      graphql_query_for(:project, { full_path: sorted_project.full_path },
        query_nodes(:ai_flow_triggers, :id, args: filter_args))
    end

    it 'returns the matching flow triggers in order' do
      post_graphql(query, current_user: current_user)

      expect(nodes).to match([a_graphql_entity_for(yankee), a_graphql_entity_for(xray)])
    end

    context 'when kind is SCHEDULED' do
      let(:filter_args) { { kind: :SCHEDULED } }

      it 'returns only the scheduled flow triggers' do
        post_graphql(query, current_user: current_user)

        expect(nodes).to match([a_graphql_entity_for(victor)])
      end
    end

    context 'when search is longer than the maximum length' do
      let(:filter_args) { { search: 'a' * 256 } }

      it 'returns a validation error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include(/search is too long/)
      end
    end

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { :NAME_ASC }
      let(:first_param) { 1 }
      let(:data_path) { [:project, :ai_flow_triggers] }
      let(:all_records) { [victor, whiskey, xray, yankee, zulu].map { |trigger| trigger.to_global_id.to_s } }

      def pagination_query(params)
        graphql_query_for(:project, { full_path: sorted_project.full_path },
          query_nodes(:ai_flow_triggers, :id, args: params, include_pagination_info: true))
      end
    end
  end

  describe 'runStats on the connection' do
    let_it_be(:created_at) { 1.day.ago.utc.noon }
    let_it_be(:sessions) do
      [[triggers[0], :finished, 60], [triggers[1], :failed, 120], [triggers[2], :finished, 300]]
        .map do |trigger, status, seconds|
          create(:duo_workflows_workflow, status, project: project, environment: :web,
            trigger_flow_trigger: trigger, service_account: trigger.service_account,
            created_at: created_at, updated_at: created_at + seconds.seconds)
        end
    end

    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{project.full_path}") {
            aiFlowTriggers(ids: ["#{triggers[0].to_global_id}", "#{triggers[1].to_global_id}"], first: 1) {
              runStats {
                totalRuns
                finishedRuns
                failedRuns
                stoppedRuns
                medianDurationSeconds
                dailyVolume { date runs }
              }
            }
          }
        }
      GQL
    end

    it 'summarizes the runs of all flow triggers that match the filters, not only the current page' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:project, :ai_flow_triggers, :run_stats)).to eq(
        'totalRuns' => 2, 'finishedRuns' => 1, 'failedRuns' => 1, 'stoppedRuns' => 0,
        'medianDurationSeconds' => 90.0,
        'dailyVolume' => [{ 'date' => created_at.to_date.iso8601, 'runs' => 2 }]
      )
    end

    it 'returns empty stats when the user cannot see the sessions' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(current_user, :duo_workflow, project).and_return(false)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:project, :ai_flow_triggers, :run_stats)).to include(
        'totalRuns' => 0, 'medianDurationSeconds' => nil, 'dailyVolume' => []
      )
    end
  end

  context 'with last run arguments' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:now) { Time.current.change(usec: 0) }
    let_it_be(:run_project) { create(:project, :in_group, maintainers: maintainer) }
    let_it_be(:never_run_a) { create(:ai_flow_trigger, project: run_project) }
    let_it_be(:never_run_b) { create(:ai_flow_trigger, project: run_project) }
    let_it_be(:succeeded) { create(:ai_flow_trigger, project: run_project) }
    let_it_be(:schedule_failed) { create(:ai_flow_trigger, :autonomous, project: run_project) }
    let_it_be(:running) { create(:ai_flow_trigger, :for_catalog_consumer, project: run_project) }
    let_it_be(:awaiting) { create(:ai_flow_trigger, project: run_project) }

    let(:query) do
      graphql_query_for(:project, { full_path: run_project.full_path },
        query_nodes(:ai_flow_triggers, :id, args: filter_args))
    end

    def create_run(flow_trigger, status, created_at, service_account: flow_trigger.service_account)
      create(:duo_workflows_workflow, status, project: run_project, environment: :web, created_at: created_at,
        trigger_flow_trigger: flow_trigger, service_account: service_account)
    end

    def global_ids(names)
      names.map { |name| public_send(name).to_global_id.to_s }
    end

    def pagination_query(params)
      graphql_query_for(:project, { full_path: run_project.full_path },
        query_nodes(:ai_flow_triggers, :id, args: params, include_pagination_info: true))
    end

    before_all do
      create_run(awaiting, :input_required, now - 5.days)
      create_run(succeeded, :finished, now - 3.days)
      create_run(succeeded, :finished, now - 2.days)
      create(:ai_flow_schedule, flow_trigger: succeeded, last_run_status: :execution_error, last_run_at: now - 2.days)
      create(:ai_flow_schedule, flow_trigger: never_run_a, last_run_status: :success, last_run_at: now - 1.day)
      create_run(never_run_b, :finished, now, service_account: succeeded.service_account)
      create_run(schedule_failed, :finished, now - 3.days)
      create(:ai_flow_schedule, flow_trigger: schedule_failed, last_run_status: :sa_invalid, last_run_at: now - 1.day)
      create_run(running, :finished, now - 40.days)
      create_run(running, :running, now - 1.hour)
    end

    where(:filter_args, :expected) do
      { last_run_status: :NEVER }          | %i[never_run_b never_run_a]
      { last_run_status: :FAILED }         | %i[schedule_failed]
      { last_run_status: :SUCCEEDED }      | %i[succeeded]
      { last_run_status: :RUNNING }        | %i[running]
      { last_run_status: :AWAITING_INPUT } | %i[awaiting]
      { sort: :LAST_RUN_DESC }             | %i[running schedule_failed succeeded awaiting never_run_b never_run_a]
      { sort: :TOTAL_RUNS_ASC }            | %i[never_run_a never_run_b schedule_failed running awaiting succeeded]
      { last_run_status: :NEVER, sort: :TOTAL_RUNS_ASC } | %i[never_run_a never_run_b]
    end

    with_them do
      it 'returns the matching flow triggers in order' do
        post_graphql(query, current_user: current_user)

        expect(nodes.pluck('id')).to eq(global_ids(expected))
      end
    end

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { :LAST_RUN_ASC }
      let(:first_param) { 5 }
      let(:data_path) { [:project, :ai_flow_triggers] }
      let(:all_records) { global_ids(%i[awaiting succeeded schedule_failed running never_run_a never_run_b]) }
    end

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { :TOTAL_RUNS_DESC }
      let(:first_param) { 2 }
      let(:data_path) { [:project, :ai_flow_triggers] }
      let(:all_records) { global_ids(%i[succeeded awaiting running schedule_failed never_run_b never_run_a]) }
    end
  end

  context 'when ids argument present' do
    let(:args) do
      <<~GQL
        (ids: [
          "#{triggers[0].to_global_id}",
          "#{triggers[1].to_global_id}",
          "#{other_trigger.to_global_id}"
        ])
      GQL
    end

    it 'returns flow triggers for project with ids' do
      post_graphql(query, current_user: current_user)

      expect(nodes).to contain_exactly(a_graphql_entity_for(triggers[0]), a_graphql_entity_for(triggers[1]))
    end
  end

  describe 'run data' do
    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{project.full_path}") {
            aiFlowTriggers#{args} {
              nodes {
                id
                runningCount
                lastRun { status }
                #{sessions_field}
              }
            }
          }
        }
      GQL
    end

    let(:sessions_field) { '' }

    def create_trigger_session(flow_trigger, status)
      create(:duo_workflows_workflow, status, project: project, environment: :web,
        trigger_flow_trigger: flow_trigger, service_account: flow_trigger.service_account)
    end

    it 'returns the run data without a query for each flow trigger', :request_store do
      create_trigger_session(triggers.first, :running)
      create_trigger_session(create(:ai_flow_trigger, :for_catalog_consumer, project: project), :finished)
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_graphql(query, current_user: current_user) }

      expect(nodes).to include(
        a_graphql_entity_for(triggers.first, running_count: 1, last_run: { 'status' => 'RUNNING' }),
        a_graphql_entity_for(triggers.second, running_count: 0, last_run: nil)
      )

      create_trigger_session(create(:ai_flow_trigger, :for_catalog_consumer, project: project), :finished)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
    end

    context 'when sessions are requested' do
      let(:args) { "(ids: [\"#{triggers.first.to_global_id}\"])" }
      let(:sessions_field) { 'sessions { nodes { id } }' }

      it 'returns the sessions of the flow trigger, newest first' do
        older_session = create_trigger_session(triggers.first, :finished)
        newer_session = create_trigger_session(triggers.first, :running)

        post_graphql(query, current_user: current_user)

        expect(nodes.first.dig('sessions', 'nodes')).to eq(
          [newer_session, older_session].map { |session| { 'id' => session.to_global_id.to_s } }
        )
      end
    end
  end
end
