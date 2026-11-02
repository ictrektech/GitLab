# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Repositories::AddCommitService, feature_category: :mcp_server do
  include ProjectForksHelper

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository) }

  let(:service) { described_class.new(name: 'add_commit') }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe 'class configuration' do
    it 'registers version 0.1.0' do
      expect(described_class.available_versions).to contain_exactly('0.1.0')
    end

    it 'identifies the tool as a destructive write operation' do
      expect(service.annotations).to eq({ readOnlyHint: false, destructiveHint: true })
    end

    it 'keeps the tool it replaces working through an alias' do
      expect(described_class.tool_aliases).to contain_exactly('create_commit')
    end

    it 'is resolvable by its alias through the manager' do
      expect(Mcp::Tools::Manager.new.get_tool(name: 'create_commit')).to be_a(described_class)
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        properties: {
          url: { type: 'string', description: 'GitLab URL of the project. Provide this or project_id.' },
          project_id: { type: 'string', description: 'ID or path of the project. Provide this or url.' },
          branch: { type: 'string', description: 'Name of the branch to commit into.' },
          start_branch: {
            type: 'string',
            description: 'Name of the branch from which to create a new branch. ' \
              'Required when branch does not exist yet.'
          },
          start_sha: {
            type: 'string',
            description: 'SHA of the commit to start a new branch from. ' \
              'Mutually exclusive with start_branch.'
          },
          start_project: {
            type: 'string',
            description: 'Full path of the project to start the commit from. Must be the ' \
              'project itself or a project it was forked from.'
          },
          commit_message: { type: 'string', description: 'Commit message.' },
          actions: {
            type: 'array',
            description: 'File actions to commit as a single batch.',
            minItems: 1,
            maxItems: 100,
            items: {
              type: 'object',
              properties: {
                action: {
                  type: 'string',
                  enum: %w[create update delete move chmod],
                  description: 'Action to perform.'
                },
                file_path: { type: 'string', description: 'Full path to the file.' },
                content: {
                  type: 'string',
                  description: 'File content for create, update, or move actions. ' \
                    'Mutually exclusive with old_str and new_str.'
                },
                old_str: {
                  type: 'string',
                  description: 'Existing text to replace in an update action. Requires new_str.'
                },
                new_str: { type: 'string', description: 'Replacement text for old_str in an update action.' },
                previous_path: { type: 'string', description: 'Original file path for a move action.' },
                encoding: {
                  type: 'string',
                  enum: %w[text base64],
                  description: 'Encoding of the file content.'
                },
                last_commit_id: {
                  type: 'string',
                  description: 'Last commit that touched the file, used for optimistic concurrency.'
                },
                execute_filemode: { type: 'boolean', description: 'Whether the file is executable.' }
              },
              required: %w[action file_path],
              additionalProperties: false
            }
          }
        },
        required: %w[branch commit_message actions]
      })
    end
  end

  describe '#governed_containers' do
    let_it_be(:upstream) { create(:project) }

    it 'governs the call by the project and the project it starts from', :aggregate_failures do
      arguments = { project_id: project.full_path, start_project: upstream.full_path }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.containers).to contain_exactly(project, upstream)
      expect(resolved.named).to eq(2)
    end
  end

  describe '#execute' do
    let(:params) do
      {
        arguments: {
          project_id: project.full_path,
          branch: project.default_branch,
          commit_message: 'Add MCP test file',
          actions: [{ action: 'create', file_path: 'mcp-test.txt', content: 'Test content' }]
        }
      }
    end

    it 'creates a commit through the GraphQL mutation' do
      result = service.execute(params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent].dig('commit', 'sha')).to be_present
      expect(project.repository.blob_at_branch(project.default_branch, 'mcp-test.txt').data).to eq('Test content')
    end

    context 'when the project identifier is missing or doubled' do
      let(:valid_rest) do
        {
          branch: 'main',
          commit_message: 'Valid everywhere but the identifier',
          actions: [{ action: 'create', file_path: 'x.txt', content: 'x' }]
        }
      end

      it 'refuses a call with neither or both identifiers', :aggregate_failures do
        both = valid_rest.merge(
          project_id: project.full_path,
          url: "#{Gitlab.config.gitlab.url}/#{project.full_path}"
        )

        [valid_rest, both].each do |arguments|
          result = service.execute(params: { arguments: arguments })

          expect(result[:isError]).to be(true)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
          expect(result.dig(:content, 0, :text)).to eq('Provide exactly one of project_id or url')
        end
      end
    end

    context 'when reading the file for a partial edit fails' do
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: project.default_branch,
            commit_message: 'Partial edit',
            actions: [{ action: 'update', file_path: 'README.md', old_str: 'Sample', new_str: 'MCP' }]
          }
        }
      end

      it 'reports an uncategorized read failure as an error, not a bad request' do
        allow_next_instance_of(Mcp::Tools::Repositories::BlobsTool) do |tool|
          allow(tool).to receive(:execute).and_return(Mcp::Tools::Base::Response.error('Internal server error'))
        end

        result = service.execute(params: params)

        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it "forwards the read failure's own reason" do
        allow_next_instance_of(Mcp::Tools::Repositories::BlobsTool) do |tool|
          allow(tool).to receive(:execute).and_return(
            Mcp::Tools::Base::Response.error(
              'Operation returned no data', reason: Mcp::Tools::Base::Response::Reason::NOT_FOUND
            )
          )
        end

        result = service.execute(params: params)

        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'when starting a new branch from a sha' do
      let(:start_sha) { project.repository.commit("#{project.default_branch}~1").sha }
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: 'from-sha-branch',
            start_sha: start_sha,
            commit_message: 'Commit from sha',
            actions: [{ action: 'create', file_path: 'from-sha.txt', content: 'x' }]
          }
        }
      end

      it 'creates the branch from the given sha', :aggregate_failures do
        result = service.execute(params: params)

        expect(result[:isError]).to be(false)
        expect(project.repository.commit('from-sha-branch').parent_ids).to contain_exactly(start_sha)
      end

      context 'with start_branch as well' do
        let(:params) do
          super().tap { |p| p[:arguments][:start_branch] = project.default_branch }
        end

        it 'surfaces the mutual-exclusion error', :aggregate_failures do
          result = service.execute(params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include('Only one of [startBranch, startSha] arguments is allowed')
        end
      end
    end

    context 'when a partial edit seeds a new branch from a sha' do
      let(:start_sha) { project.repository.commit(project.default_branch).sha }
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: 'partial-from-sha',
            start_sha: start_sha,
            commit_message: 'Partial edit from sha',
            actions: [{ action: 'update', file_path: 'README.md', old_str: 'Sample repo', new_str: 'MCP' }]
          }
        }
      end

      it 'reads the file at the sha instead of the not-yet-existing branch', :aggregate_failures do
        result = service.execute(params: params)

        expect(result[:isError]).to be(false)
        expect(project.repository.commit('partial-from-sha').parent_ids).to contain_exactly(start_sha)
        expect(project.repository.blob_at_branch('partial-from-sha', 'README.md').data).to include('MCP')
      end
    end

    context 'when a partial edit is combined with start_project' do
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: 'partial-start-project',
            start_sha: project.repository.commit(project.default_branch).sha,
            start_project: project.full_path,
            commit_message: 'x',
            actions: [{ action: 'update', file_path: 'README.md', old_str: 'a', new_str: 'b' }]
          }
        }
      end

      it 'rejects the combination with a self-correcting error', :aggregate_failures do
        result = service.execute(params: params)

        expect(result[:isError]).to be(true)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
        expect(result.dig(:content, 0, :text)).to include('not supported with start_project')
      end
    end

    context 'when old_str holds only whitespace' do
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: project.default_branch,
            commit_message: 'x',
            actions: [{
              action: 'update', file_path: 'README.md',
              old_str: "\n\n\n", new_str: '', content: 'whole file'
            }]
          }
        }
      end

      it 'still counts as a partial edit instead of committing content blindly', :aggregate_failures do
        result = service.execute(params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('not both')
      end
    end

    context 'when an update has neither content nor a partial edit' do
      where(:empty_fields) do
        [
          [{ old_str: '', new_str: '' }],
          [{ content: '', old_str: '', new_str: '' }]
        ]
      end

      with_them do
        let(:params) do
          {
            arguments: {
              project_id: project.full_path,
              branch: project.default_branch,
              commit_message: 'x',
              actions: [{ action: 'update', file_path: 'README.md' }.merge(empty_fields)]
            }
          }
        end

        it 'refuses it instead of emptying the file', :aggregate_failures do
          head_sha = project.repository.commit(project.default_branch).sha

          result = service.execute(params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include('Provide content, or old_str and new_str')
          expect(project.repository.commit(project.default_branch).sha).to eq(head_sha)
        end
      end
    end

    context 'when starting from a forked project' do
      let_it_be(:forked_project) { fork_project(project, nil, repository: true) }

      let(:start_sha) { project.repository.commit(project.default_branch).sha }
      let(:params) do
        {
          arguments: {
            project_id: forked_project.full_path,
            branch: 'from-upstream',
            start_sha: start_sha,
            start_project: project.full_path,
            commit_message: 'Commit from upstream',
            actions: [{ action: 'create', file_path: 'from-upstream.txt', content: 'x' }]
          }
        }
      end

      before_all do
        forked_project.add_developer(user)
      end

      it 'creates the branch starting from the upstream project', :aggregate_failures do
        result = service.execute(params: params)

        expect(result[:isError]).to be(false)
        expect(forked_project.repository.commit('from-upstream')).to be_present
      end

      context 'when the start project is outside the fork network' do
        let_it_be(:unrelated) { create(:project, :public, :repository) }

        let(:params) do
          super().tap { |p| p[:arguments][:start_project] = unrelated.full_path }
        end

        it 'rejects it with the uniform fork-network error', :aggregate_failures do
          result = service.execute(params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include('fork network')
        end
      end
    end

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response' do
        result = service.execute(params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('current_user is not set')
      end
    end

    context 'with a partial edit' do
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            branch: project.default_branch,
            commit_message: 'Update README',
            actions: [{ action: 'update', file_path: 'README.md', old_str: 'Sample repo', new_str: 'MCP' }]
          }
        }
      end

      it 'expands and commits the partial edit' do
        result = service.execute(params: params)

        expect(result[:isError]).to be(false)
        expect(project.repository.blob_at_branch(project.default_branch, 'README.md').data).to include('MCP')
      end

      # The truncation guard fails closed, so size dropping out of the shared
      # get_repository_file query would reject every partial edit.
      it 'gets a blob size back from the shared query' do
        nodes = service.send(:read_blobs, params[:arguments].with_indifferent_access, ['README.md'])
          .dig(:structuredContent, 'repository', 'blobs', 'nodes')

        expect(nodes.first['size']).to be_present
      end
    end
  end

  describe 'partial edit expansion' do
    let(:base_arguments) do
      {
        project_id: project.full_path,
        branch: project.default_branch,
        commit_message: 'Partial edit',
        actions: [{ action: 'update', file_path: 'README.md', old_str: 'old', new_str: 'new' }]
      }
    end

    let(:blob_content) { 'before old after' }
    let(:lfs_pointer) do
      "version https://git-lfs.github.com/spec/v1\noid sha256:#{'a' * 64}\nsize 1024\n"
    end

    let(:blob_result) do
      Mcp::Tools::Base::Response.success([], {
        'repository' => {
          'blobs' => { 'nodes' => [{
            'path' => 'README.md', 'size' => blob_content.bytesize, 'rawTextBlob' => blob_content
          }] }
        }
      })
    end

    before do
      blobs_tool = instance_double(Mcp::Tools::Repositories::BlobsTool, execute: blob_result)
      allow(Mcp::Tools::Repositories::BlobsTool).to receive(:new).and_return(blobs_tool)
    end

    it 'expands a unique match and preserves replacement backslashes' do
      base_arguments[:actions][0][:new_str] = '\\1 replacement'

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(content: 'before \\1 replacement after')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'returns an error when old_str is not found' do
      base_arguments[:actions][0][:old_str] = 'missing'

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:content].first[:text]).to include('old_str was not found')
    end

    it 'returns an error when old_str is ambiguous' do
      base_arguments[:actions][0][:old_str] = 'old'
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{ 'path' => 'README.md', 'size' => 7, 'rawTextBlob' => 'old old' }] }
          }
        })
      )

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:content].first[:text]).to include('old_str is ambiguous')
    end

    where(:changes, :error) do
      [
        [{ content: 'complete' }, 'Provide either content'],
        [{ action: 'create' }, 'only supported for update'],
        [{ encoding: 'base64' }, 'require text encoding']
      ]
    end

    with_them do
      it 'rejects an invalid partial edit' do
        base_arguments[:actions][0].merge!(changes)

        result = service.send(:perform_v0_1_0, base_arguments)

        expect(result[:content].first[:text]).to include(error)
      end
    end

    it 'returns an error for a binary file' do
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{ 'path' => 'README.md', 'size' => 1024, 'rawTextBlob' => nil }] }
          }
        })
      )

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:content].first[:text]).to include('is binary')
    end

    it 'returns an error for a file stored in LFS', :aggregate_failures do
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{
              'path' => 'data.csv', 'size' => '134', 'rawTextBlob' => lfs_pointer,
              'storedExternally' => true, 'externalStorage' => 'lfs'
            }] }
          }
        })
      )
      base_arguments[:actions][0].merge!(file_path: 'data.csv', old_str: 'size 1024', new_str: 'size 2048')

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include("File 'data.csv' is stored in LFS (lfs)")
    end

    it 'returns an error for a file larger than the display limit', :aggregate_failures do
      # A string, because the GraphQL size field is a BigInt and serializes that way.
      oversized = (Gitlab::Git::Blob::MAX_DATA_DISPLAY_SIZE + 1).to_s
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{ 'path' => 'README.md', 'size' => oversized, 'rawTextBlob' => 'old' }] }
          }
        })
      )

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('exceeds the 10 MiB partial-edit size limit')
    end

    it 'returns an error when the blob size is unknown', :aggregate_failures do
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{ 'path' => 'README.md', 'size' => nil, 'rawTextBlob' => 'before old after' }] }
          }
        })
      )

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('has an unknown size')
    end

    it 'accepts a file exactly at the display limit', :aggregate_failures do
      # truncated? reads only size, never the content length, so a fixture claiming the
      # full limit while carrying 16 bytes costs nothing and pins the > (not >=) boundary.
      # Real 10 MiB content would allocate 10 MiB per run and cover no extra branch.
      at_limit = Gitlab::Git::Blob::MAX_DATA_DISPLAY_SIZE
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{
              'path' => 'README.md', 'size' => at_limit, 'rawTextBlob' => 'before old after'
            }] }
          }
        })
      )

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(content: 'before new after')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:isError]).to be(false)
    end

    it 'applies multiple edits to the same path in sequence' do
      base_arguments[:actions] << {
        action: 'update', file_path: 'README.md', old_str: 'new', new_str: 'newest'
      }

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(content: 'before new after'), hash_including(content: 'before newest after')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'handles non-ASCII fragments' do
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{ 'path' => 'README.md', 'size' => 'héllo'.bytesize, 'rawTextBlob' => 'héllo' }] }
          }
        })
      )
      base_arguments[:actions][0].merge!(old_str: 'héllo', new_str: 'नमस्ते')

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(content: 'नमस्ते')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'wraps a blob read error with partial edit context' do
      allow(service).to receive(:read_blobs).and_return(
        Mcp::Tools::Base::Response.error('Max blobs size limit exceeded')
      )

      result = service.send(:perform_v0_1_0, base_arguments)

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include(
        'Could not read the file(s) needed to expand the partial edit',
        'Max blobs size limit exceeded'
      )
    end

    it 'does not swallow an unrelated ArgumentError raised while running the mutation' do
      allow(service).to receive(:execute_graphql_tool).and_raise(ArgumentError, 'URL must identify a project')

      expect { service.send(:perform_v0_1_0, base_arguments) }
        .to raise_error(ArgumentError, 'URL must identify a project')
    end

    it 'passes the access token to the blobs tool' do
      access_token = build_stubbed(:personal_access_token, user: user)
      service.set_cred(current_user: user, access_token: access_token)

      expect(Mcp::Tools::Repositories::BlobsTool).to receive(:new)
        .with(hash_including(access_token: access_token))
        .and_return(instance_double(Mcp::Tools::Repositories::BlobsTool, execute: blob_result))
      expect(service).to receive(:execute_graphql_tool).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'reads from branch, not start_branch, when branch already exists' do
      base_arguments[:start_branch] = 'nonexistent-start-branch'

      expect(Mcp::Tools::Repositories::BlobsTool).to receive(:new)
        .with(hash_including(params: hash_including(ref: project.default_branch)))
        .and_return(instance_double(Mcp::Tools::Repositories::BlobsTool, execute: blob_result))
      expect(service).to receive(:execute_graphql_tool).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'reads from start_branch when branch does not exist yet' do
      base_arguments[:branch] = 'brand-new-feature-branch'
      base_arguments[:start_branch] = project.default_branch

      expect(Mcp::Tools::Repositories::BlobsTool).to receive(:new)
        .with(hash_including(params: hash_including(ref: project.default_branch)))
        .and_return(instance_double(Mcp::Tools::Repositories::BlobsTool, execute: blob_result))
      expect(service).to receive(:execute_graphql_tool).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end

    it 'treats empty-string old_str and new_str as absent' do
      arguments = {
        project_id: project.full_path,
        branch: project.default_branch,
        commit_message: 'Create file with GPT defaults',
        actions: [{
          action: 'create', file_path: 'gpt-default.txt', content: 'hello',
          old_str: '', new_str: '', previous_path: '', last_commit_id: '', execute_filemode: false
        }]
      }

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(action: 'create', file_path: 'gpt-default.txt', content: 'hello')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, arguments)
    end

    it 'treats an empty-string content as absent on a partial edit' do
      base_arguments[:actions][0][:content] = ''

      expect(service).to receive(:execute_graphql_tool).with(hash_including(
        actions: [hash_including(content: 'before new after')]
      )).and_return(Mcp::Tools::Base::Response.success([]))

      service.send(:perform_v0_1_0, base_arguments)
    end
  end

  describe 'commit size limits' do
    using RSpec::Parameterized::TableSyntax

    # The commit message and file path add 11 bytes, so content of N bytes totals N + 11.
    let(:content) { 'a' * 10 }
    let(:arguments) do
      {
        project_id: project.full_path,
        branch: project.default_branch,
        commit_message: 'Add',
        actions: [{ action: 'create', file_path: 'file.txt', content: content }]
      }
    end

    let(:success) { Mcp::Tools::Base::Response.success([]) }

    before do
      stub_const('Repositories::CommitsUploader::MAX_RATE_LIMITED_REQUEST_SIZE', 30)
      stub_env('GITLAB_COMMITS_MAX_REQUEST_SIZE_BYTES', 100)
      allow(service).to receive(:execute_graphql_tool).and_return(success)
    end

    def perform
      service.send(:perform_v0_1_0, arguments)
    end

    context 'when the commit is at or under the large-commit threshold' do
      let(:content) { 'a' * 19 }

      it 'commits without calling the rate limiter' do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect(perform).to eq(success)
      end
    end

    context 'when several actions together are over the large-commit threshold' do
      before do
        arguments[:actions] = %w[a.txt b.txt c.txt].map do |path|
          { action: 'create', file_path: path, content: content }
        end
      end

      it 'counts every action' do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(false)

        expect(perform).to eq(success)
      end
    end

    context 'when the commit is over the large-commit threshold and within the cap' do
      let(:content) { 'a' * 20 }

      it 'checks the large-commit rate limit and commits when not throttled' do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:user_large_commit_request, scope: { user: user }).and_return(false)

        expect(perform).to eq(success)
      end

      it 'returns a rate-limited error without committing when throttled', :aggregate_failures do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(true)

        expect(service).not_to receive(:execute_graphql_tool)

        result = perform

        expect(result[:isError]).to be(true)
        expect(result.dig(:structuredContent, :error)).to include(
          type: 'rate_limited', limit: 'user_large_commit_request'
        )
      end

      context 'when the content is base64 encoded' do
        let(:content) { Base64.strict_encode64('a' * 15) }

        it 'counts the encoded length' do
          arguments[:actions][0][:encoding] = 'base64'

          expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(false)

          perform
        end
      end

      context 'when the commit is exactly at the request size cap' do
        let(:content) { 'a' * 89 }

        it 'checks the large-commit rate limit instead of rejecting it' do
          expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(false)

          expect(perform).to eq(success)
        end
      end
    end

    context 'when the commit is over the request size cap' do
      let(:content) { 'a' * 90 }

      it 'returns a bad request error without calling the limiter or committing', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
        expect(service).not_to receive(:execute_graphql_tool)

        result = perform

        expect(result[:isError]).to be(true)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
        expect(result.dig(:content, 0, :text)).to eq('The commit exceeds the 100 B request size limit')
      end
    end

    context 'when a partial edit expands into large content' do
      let(:blob_content) { "old#{'a' * 90}" }
      let(:arguments) do
        {
          project_id: project.full_path,
          branch: project.default_branch,
          commit_message: 'Add',
          actions: [{ action: 'update', file_path: 'file.txt', old_str: 'old', new_str: 'new' }]
        }
      end

      before do
        blob_result = Mcp::Tools::Base::Response.success([], {
          'repository' => {
            'blobs' => { 'nodes' => [{
              'path' => 'file.txt', 'size' => blob_content.bytesize, 'rawTextBlob' => blob_content
            }] }
          }
        })
        blobs_tool = instance_double(Mcp::Tools::Repositories::BlobsTool, execute: blob_result)
        allow(Mcp::Tools::Repositories::BlobsTool).to receive(:new).and_return(blobs_tool)
      end

      it 'counts the expanded content' do
        expect(service).not_to receive(:execute_graphql_tool)

        expect(Mcp::Tools::Base::Response.error_reason(perform)).to eq(:bad_request)
      end
    end

    context 'when the mcp_add_commit_size_limits feature flag is disabled' do
      before do
        stub_feature_flags(mcp_add_commit_size_limits: false)
      end

      where(:content_size, :rule) do
        90 | 'max_request_size'
        20 | 'user_large_commit_request'
      end

      with_them do
        let(:content) { 'a' * content_size }

        it 'commits and logs the limit that would apply without calling the limiter', :aggregate_failures do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
          expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
            message: 'MCP add_commit would exceed a commit size limit',
            Labkit::Fields::GL_USER_ID => user.id,
            rule: rule,
            total_bytes: content_size + 11
          )).and_call_original

          expect(perform).to eq(success)
        end
      end

      it 'does not log a commit under the large-commit threshold' do
        expect(Gitlab::AppLogger).not_to receive(:info)

        perform
      end
    end

    context 'with the real rate limiter', :clean_gitlab_redis_rate_limiting do
      let(:content) { 'a' * 20 }

      it 'rate limits the fourth large commit in a row', :aggregate_failures do
        3.times { expect(perform).to eq(success) }

        result = perform

        expect(result[:isError]).to be(true)
        expect(result.dig(:structuredContent, :error, :type)).to eq('rate_limited')
      end
    end
  end
end
