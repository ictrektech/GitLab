# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'governable MCP tools resolve a container', feature_category: :ai_agents do
  let_it_be(:namespace) { create(:group) }

  let(:governed_tools) do
    ::Ai::ToolRules::GovernedMcpTools.for(namespace)
  end

  let(:manager) { ::Mcp::Tools::Manager.new }

  let(:not_a_container) do
    {
      'accept_merge_request' => %w[commit_message merge_request_iid sha should_remove_source_branch squash
        squash_commit_message strategy],
      'add_branch' => %w[branch ref],
      'add_commit' => %w[actions branch commit_message start_branch start_sha],
      'create_issue' => %w[assignee_ids confidential description labels milestone milestone_id title],
      'fork_repository' => %w[description name path visibility],
      'get_artifact_file' => %w[artifact_path byte_limit byte_offset file_type job_id],
      'get_commit' => %w[commit_sha diff_detail include notes_after notes_first],
      'get_issue' => %w[issue_iid],
      'get_job' => %w[byte_limit byte_offset from include job_id],
      'get_merge_request' => %w[commits_after commits_first detail diffs_after diffs_first include merge_request_iid
        notes_after notes_before notes_first notes_last pipelines_after pipelines_first],
      'get_merge_request_commits' => %w[merge_request_iid page per_page],
      'get_merge_request_conflicts' => %w[merge_request_iid],
      'get_merge_request_diffs' => %w[merge_request_iid page per_page],
      'get_merge_request_notes' => %w[after before first last merge_request_iid],
      'get_merge_request_pipelines' => %w[merge_request_iid],
      'get_pages_content' => %w[byte_limit byte_offset],
      'get_pipeline' => %w[after first include job_status pipeline_id],
      'get_pipeline_jobs' => %w[page per_page pipeline_id],
      'get_repository_file' => %w[file_path limit offset ref],
      'get_saved_view_work_items' => %w[after first],
      'get_work_item' => %w[discussions_after discussions_filter discussions_first include mr_page_size
        mr_pagination_cursor notes_after notes_before notes_first notes_last related_merge_requests_after
        related_merge_requests_first work_item_iid],
      'get_workitem_notes' => %w[after before first last work_item_iid],
      'link_work_items' => %w[link_type work_item_iid],
      'list_branches' => %w[page per_page search],
      'list_commits' => %w[after author first first_parent order path ref_name since until with_stats],
      'list_duo_agents_and_flows' => %w[after first item_type],
      'list_duo_sessions' => %w[after first status_group statuses],
      'list_groups' => %w[after first include_subgroups search visibility],
      'list_merge_requests' => %w[after assignee_username author_username first labels milestone reviewer_username
        scope search state],
      'list_pipelines' => %w[created_after created_before order_by page per_page ref sort source status],
      'list_project_members' => %w[after first include_inherited query],
      'list_projects' => %w[after archived first min_access_level search visibility],
      'list_releases' => %w[page per_page state],
      'list_repository_tree' => %w[after path recursive ref],
      'list_tags' => %w[after first search],
      'list_todos' => %w[action after author_id first state type],
      'list_vulnerabilities' => %w[after first report_type severity state],
      'list_wiki_pages' => %w[after first],
      'list_work_items' => %w[after assignee_usernames author_username created_after created_before due_after
        due_before first health_status_filter label_name milestone_title milestone_wildcard_id parent_iid search
        sort state status types updated_after updated_before],
      'manage_pipeline' => %w[name pipeline_id],
      'save_merge_request' => %w[add_labels allow_collaboration assignee_ids assignees description discussion_locked
        labels merge_request_iid milestone milestone_id remove_labels remove_source_branch reviewer_ids reviewers
        source_branch squash state_event target_branch title],
      'save_merge_request_review' => %w[body comments discussion_id internal merge_request_iid method new_line
        new_path old_line old_path resolved sha summary summary_internal verdict],
      'save_note' => %w[body discussion_id internal merge_request_iid method resolved work_item_iid],
      'save_pipeline' => %w[action inputs name ref variables],
      'save_project' => %w[default_branch description group_with_project_templates_id initialize_with_readme name
        path template_name template_project_id topics use_custom_template visibility],
      'save_vulnerability' => %w[action comment dismissal_reason severity],
      'save_work_item' => %w[add_label_ids add_labels agent_plan assignee_ids clear_weight confidential description
        due_date health_status is_fixed label_ids labels milestone milestone_id readiness_score remove_label_ids
        remove_labels start_date state status_id title todo_action todo_id type_name weight work_item_iid],
      'search' => %w[confidential order_by page per_page scope search sort state type],
      'search_labels' => %w[is_project search],
      'semantic_search' => %w[directory_path knn limit q scope],
      'start_duo_session' => %w[agent flow flow_item_id goal]
    }.freeze
  end

  before do
    stub_feature_flags(duo_mcp_tool_governance: namespace)
  end

  it 'declares a namespace argument for every governable tool' do
    missing = governed_tools.names.reject do |name|
      tool = manager.list_tools[name]

      tool.ungovernable? || tool.container_arguments.present?
    end

    expect(missing).to be_empty,
      "these tools are governable but declare no scope, so their rules are never enforced: #{missing.join(', ')}"
  end

  it 'declares at least one argument the tool actually accepts' do
    unresolvable = governed_tools.names.reject do |name|
      tool = manager.list_tools[name]
      next true if tool.ungovernable?

      schema = tool.input_schema
      accepted = (schema[:properties] || schema['properties'] || {}).keys.map(&:to_s)

      (tool.declared_argument_names & accepted).any?
    end

    expect(unresolvable).to be_empty,
      "these tools declare no scope argument they accept, so their rules never apply: #{unresolvable.join(', ')}"
  end

  it 'declares the url argument for every governable tool that accepts one' do
    undeclared = governed_tools.names.reject do |name|
      tool = manager.list_tools[name]
      next true if tool.ungovernable?

      schema = tool.input_schema
      accepted = (schema[:properties] || schema['properties'] || {}).keys.map(&:to_s)

      next true unless accepted.include?('url')

      tool.declared_argument_names.include?('url')
    end

    expect(undeclared).to be_empty,
      "these tools accept a url but do not declare it, so calling them by url is ungoverned: " \
        "#{undeclared.join(', ')}"
  end

  it 'resolves every record argument it declares' do
    unresolved = governed_tools.names.select do |name|
      tool = manager.list_tools[name]
      record = tool.container_arguments[:record]
      next false if record.blank?
      next false if record.is_a?(Hash)

      tool.class.instance_method(:governed_containers).owner ==
        ::Mcp::Tools::Concerns::GovernanceContainerResolver
    end

    expect(unresolved).to be_empty,
      "these tools name a record argument without giving it a resolver and without overriding " \
        "governed_containers, so the record is never resolved: #{unresolved.join(', ')}"
  end

  it 'classifies every input property of every governable tool' do
    unclassified = governed_tools.names.flat_map do |name|
      tool = manager.list_tools[name]
      next [] if tool.ungovernable?

      unclassified = accepted_properties(tool) - tool.declared_argument_names - not_a_container.fetch(name, [])
      unclassified.map { |property| "#{name}.#{property}" }
    end

    expect(unclassified).to be_empty,
      "these input properties are classified as neither a scope argument, a record argument, " \
        "nor an argument this tool never points at a project or group, so nobody has decided " \
        "whether a rule should follow them: #{unclassified.join(', ')}"
  end

  it 'lists as never a container only arguments the tool accepts and does not declare' do
    stale = not_a_container.flat_map do |name, properties|
      tool = manager.list_tools[name]
      next ["#{name} (not a tool)"] unless tool

      unclassified = accepted_properties(tool) - tool.declared_argument_names
      (properties - unclassified).map { |property| "#{name}.#{property}" }
    end

    expect(stale).to be_empty,
      "these entries name an argument the tool does not accept or already declares: #{stale.join(', ')}"
  end

  it 'keys every declaration on a kind the resolver reads' do
    resolver = ::Mcp::Tools::Concerns::GovernanceContainerResolver
    recognized = resolver::CONTAINER_KINDS + %i[record]

    unknown = governed_tools.names.filter_map do |name|
      keys = manager.list_tools[name].container_arguments.keys - recognized
      "#{name} (#{keys.join(', ')})" if keys.any?
    end

    expect(unknown).to be_empty,
      "these tools declare a namespace kind nothing resolves, so they are never governed: #{unknown.join(', ')}"
  end

  def accepted_properties(tool)
    schema = tool.input_schema

    (schema[:properties] || schema['properties'] || {}).keys.map(&:to_s)
  end
end
