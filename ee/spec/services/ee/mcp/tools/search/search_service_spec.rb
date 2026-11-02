# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Search::SearchService, feature_category: :mcp_server do
  let(:mock_tool_global) { instance_double(Mcp::Tools::Base::ApiTool, name: :gitlab_search_in_instance) }
  let(:mock_tool_group) { instance_double(Mcp::Tools::Base::ApiTool, name: :gitlab_search_in_group) }
  let(:mock_tool_project) { instance_double(Mcp::Tools::Base::ApiTool, name: :gitlab_search_in_project) }
  let(:tools) { [mock_tool_global, mock_tool_group, mock_tool_project] }
  let(:service) { described_class.new(tools: tools) }

  describe '#description' do
    it 'returns the correct description' do
      expect(service.description).to eq("" \
        "Search across GitLab with automatic selection of the best available search method.\n\n" \
        "**Capabilities:** basic (keywords, file filters)\n\n" \
        "**Syntax Examples:**\n- Basic: \"bug fix\", \"filename:*.rb\", \"extension:js\"")
    end

    context 'when advanced search is enabled' do
      it 'returns the correct description' do
        stub_ee_application_setting(elasticsearch_search: true)

        expect(service.description).to include('advanced (boolean operators)')
      end
    end

    context 'when exact code search is enabled' do
      it 'returns the correct description' do
        allow(::Search::Zoekt).to receive(:search_enabled?).and_return(true)

        expect(service.description).to include('exact code (exact match, regex, symbols)')
      end
    end
  end

  describe '#input_schema' do
    let(:base_schema) do
      {
        type: 'object',
        properties: {
          scope: {
            type: 'string',
            enum: %w[projects groups work_items merge_requests milestones users snippet_titles
              blobs wiki_blobs commits notes],
            description: 'Specify the type of content to search for. Available content types vary by search ' \
              "context:\n" \
              "\n" \
              '- GitLab instance: projects, groups, work_items, merge_requests, milestones, users, ' \
              "snippet_titles\n" \
              "- Group: projects, groups, work_items, merge_requests, milestones, users\n" \
              '- Project: blobs, work_items, merge_requests, wiki_blobs, commits, notes, milestones, ' \
              "users\n" \
              "\n" \
              "Examples:\n" \
              "- Use \"work_items\" to search for issues, tasks, epics, and other work items\n" \
              "- Use \"merge_requests\" to search for merge requests\n" \
              "- Use \"blobs\" to search code files\n" \
              "- Use \"notes\" to search comments across different content\n" \
              '- Use "commits" to search commit messages'
          },
          search: {
            type: 'string',
            description: 'The term to search for'
          },
          group_id: {
            type: 'string',
            description: 'Provide to search within a group. The ID or full path of the group'
          },
          project_id: {
            type: 'string',
            description: 'Provide to search within a project. The ID or full path of the project'
          },
          state: {
            type: 'string',
            description: "Filter results by state. Available states:\n" \
              "- Work items: opened, closed\n" \
              "- Merge requests: opened, closed, merged, locked\n" \
              "\n" \
              'Only applies to work_items and merge_requests scopes.'
          },
          confidential: {
            type: 'boolean',
            description: 'Filter results by confidentiality. Available for work_items scope; other scopes are ' \
              'ignored.'
          },
          order_by: {
            type: 'string',
            description: "Specify how to order search results.\n" \
              "- Allowed values: created_at only\n" \
              "- When omitted:\n  " \
              "* Basic search: sorted by created_at descending\n  " \
              '* Advanced search: sorted by relevance'
          },
          sort: {
            type: 'string',
            description: "Specify the sort direction for results. Works with order_by parameter\n" \
              '- Allowed values: asc, desc'
          },
          per_page: {
            type: 'integer',
            description: 'Number of items to list per page.',
            minimum: 1
          },
          page: {
            type: 'integer',
            description: 'Page number to retrieve.',
            minimum: 1
          },
          type: {
            type: 'array',
            items: {
              type: 'string'
            },
            description: "Filter work items by type. Only applies to work_items scope.\n" \
              'Available types: issue, task, epic, incident, test_case, requirement, objective, ' \
              'key_result, ticket'
          }
        },
        required: %w[scope search],
        additionalProperties: false
      }
    end

    let(:regex_property) do
      {
        regex: {
          type: 'boolean',
          description: 'Performs a regex code search. Available for blobs scope; other scopes are ignored.'
        }
      }
    end

    let(:advanced_search_properties) do
      {
        scope: {
          type: 'string',
          enum: %w[projects groups blobs work_items merge_requests wiki_blobs commits notes
            milestones users snippet_titles],
          description: 'Specify the type of content to search for. Available content types vary by search ' \
            "context:\n" \
            "\n" \
            '- GitLab instance: projects, groups, blobs, work_items, merge_requests, wiki_blobs, ' \
            "commits, notes, milestones, users, snippet_titles\n" \
            '- Group: projects, groups, blobs, work_items, merge_requests, wiki_blobs, commits, ' \
            "notes, milestones, users\n" \
            '- Project: blobs, work_items, merge_requests, wiki_blobs, commits, notes, milestones, ' \
            "users\n" \
            "\n" \
            "Examples:\n" \
            "- Use \"work_items\" to search for issues, tasks, epics, and other work items\n" \
            "- Use \"merge_requests\" to search for merge requests\n" \
            "- Use \"blobs\" to search code files\n" \
            "- Use \"notes\" to search comments across different content\n" \
            '- Use "commits" to search commit messages'
        },
        fields: {
          type: 'array',
          items: {
            type: 'string'
          },
          description: "Specify which fields to search within. Currently supported:\n" \
            "- Allowed values: title only\n" \
            '- Applicable scopes: work_items, merge_requests'
        }
      }
    end

    before do
      stub_ee_application_setting(elasticsearch_search: advanced_search, elasticsearch_indexing: advanced_search)
      allow(::Search::Zoekt).to receive(:search_enabled?).and_return(exact_code_search)
    end

    context 'when neither advanced nor exact code search is enabled' do
      let(:advanced_search) { false }
      let(:exact_code_search) { false }

      it 'locks the full input schema' do
        expect(service.input_schema).to eq(base_schema)
      end
    end

    context 'when only exact code search is enabled' do
      let(:advanced_search) { false }
      let(:exact_code_search) { true }

      it 'adds the regex property' do
        expect(service.input_schema).to eq(base_schema.deep_merge(properties: regex_property))
      end
    end

    context 'when only advanced search is enabled' do
      let(:advanced_search) { true }
      let(:exact_code_search) { false }

      it 'adds the fields property and the advanced search scopes' do
        expect(service.input_schema).to eq(base_schema.deep_merge(properties: advanced_search_properties))
      end
    end

    context 'when both advanced and exact code search are enabled' do
      let(:advanced_search) { true }
      let(:exact_code_search) { true }

      it 'adds the regex and fields properties and the advanced search scopes' do
        expect(service.input_schema).to eq(
          base_schema.deep_merge(properties: advanced_search_properties.merge(regex_property))
        )
      end
    end
  end

  describe '#transform_arguments' do
    let_it_be_with_reload(:project) { create(:project) }

    subject(:transform_arguments) { service.send(:transform_arguments, args) }

    context 'when scope is blobs' do
      let(:args) { { scope: 'blobs', search: 'test query', id: project.id.to_s } }

      context 'with no exclusion rules' do
        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end

      context 'with exclusion rules' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['*.md', 'config/**/*.yml'] }
          )
        end

        it 'appends -filename: for simple patterns and -path: for path patterns' do
          result = transform_arguments
          expect(result[:search]).to eq('test query -filename:*.md -path:config/**/*.yml')
        end

        it 'preserves other arguments' do
          result = transform_arguments
          expect(result[:scope]).to eq('blobs')
          expect(result[:id]).to eq(project.id.to_s)
        end
      end

      context 'with path-based exclusion rules' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['ruby/server.rb', 'ruby/*.rb', 'ruby/*'] }
          )
        end

        it 'uses -path: filter for patterns with /' do
          result = transform_arguments
          expect(result[:search]).to eq('test query -path:ruby/server.rb -path:ruby/*.rb -path:ruby/*')
        end
      end

      context 'with filename-based exclusion rules' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['server.rb', '*.rb'] }
          )
        end

        it 'uses -filename: filter for simple patterns' do
          result = transform_arguments
          expect(result[:search]).to eq('test query -filename:server.rb -filename:*.rb')
        end
      end

      context 'with empty exclusion rules array' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: [] }
          )
        end

        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end

      context 'when project is not found' do
        let(:args) { { scope: 'blobs', search: 'test query', id: 'nonexistent' } }

        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end

      context 'when the project is pending deletion' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['*.md'] }
          )
          project.update!(pending_delete: true)
        end

        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end

      context 'when the project is hidden' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['*.md'] }
          )
          project.update!(hidden: true)
        end

        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end

      context 'when project has no settings' do
        before do
          project.project_setting&.destroy!
          project.reload
        end

        it 'returns args unchanged' do
          expect(transform_arguments).to eq(args)
        end
      end
    end

    context 'when scope is wiki_blobs' do
      let(:args) { { scope: 'wiki_blobs', search: 'test query', id: project.id.to_s } }

      context 'with filename pattern' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['*.md'] }
          )
        end

        it 'appends -filename: filters to search query' do
          result = transform_arguments
          expect(result[:search]).to eq('test query -filename:*.md')
        end
      end

      context 'with path pattern' do
        before do
          project.create_project_setting unless project.project_setting
          project.project_setting.update!(
            duo_context_exclusion_settings: { exclusion_rules: ['docs/index.md', 'docs/*'] }
          )
        end

        it 'appends -path: filters to search query' do
          result = transform_arguments
          expect(result[:search]).to eq('test query -path:docs/index.md -path:docs/*')
        end
      end
    end

    context 'when scope is not blobs or wiki_blobs' do
      let(:args) { { scope: 'work_items', search: 'test query', id: project.id.to_s } }

      before do
        project.create_project_setting unless project.project_setting
        project.project_setting.update!(
          duo_context_exclusion_settings: { exclusion_rules: ['*.md'] }
        )
      end

      it 'does not apply exclusion' do
        expect(transform_arguments).to eq(args)
      end
    end

    context 'when using project full_path' do
      let(:args) { { scope: 'blobs', search: 'test query', id: project.full_path } }

      before do
        project.create_project_setting unless project.project_setting
        project.project_setting.update!(
          duo_context_exclusion_settings: { exclusion_rules: ['*.md', 'docs/*'] }
        )
      end

      it 'finds project by full_path and applies exclusion' do
        result = transform_arguments
        expect(result[:search]).to eq('test query -filename:*.md -path:docs/*')
      end
    end

    context 'when search query is empty' do
      let(:args) { { scope: 'blobs', search: '', id: project.id.to_s } }

      before do
        project.create_project_setting unless project.project_setting
        project.project_setting.update!(
          duo_context_exclusion_settings: { exclusion_rules: ['*.md'] }
        )
      end

      it 'adds filters without leading space' do
        result = transform_arguments
        expect(result[:search]).to eq('-filename:*.md')
      end
    end

    context 'when args[:id] is nil' do
      let(:args) { { scope: 'blobs', search: 'test query', id: nil } }

      it 'returns args unchanged' do
        expect(transform_arguments).to eq(args)
      end
    end

    context 'when project settings exist but exclusion_rules key is missing' do
      let(:args) { { scope: 'blobs', search: 'test query', id: project.id.to_s } }

      before do
        project.create_project_setting unless project.project_setting
        project.project_setting.update!(
          duo_context_exclusion_settings: {}
        )
      end

      it 'returns args unchanged' do
        expect(transform_arguments).to eq(args)
      end
    end
  end
end
