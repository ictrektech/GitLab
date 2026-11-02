# frozen_string_literal: true

require 'spec_helper'
require 'google/rpc/status_pb'
require 'google/rpc/error_details_pb'

RSpec.describe Analytics::KnowledgeGraph::QueryRunner, feature_category: :knowledge_graph do
  let(:user) { build_stubbed(:user) }
  let(:handler) { ->(requests, yielder) { yielder << result_message(requests.next.request.query) } }
  let(:extra_params) { {} }
  let(:env) { {} }
  let(:params) do
    {
      'GkgServer' => { 'address' => "127.0.0.1:#{port}", 'headers' => {} },
      'Query' => '{"query_type":"search"}',
      'Format' => 'raw'
    }.merge(extra_params)
  end

  let(:grpc_server) { GRPC::RpcServer.new(pool_size: 2, poll_period: 0.1) }
  let(:port) { grpc_server.add_http2_port('127.0.0.1:0', :this_port_is_insecure) }
  let(:server_calls) { Queue.new }
  let(:fake_service) do
    current_handler = handler
    calls = server_calls
    Class.new(::Orbit::V1::OrbitService::Service) do
      define_method(:execute_query) do |requests, call|
        Enumerator.new do |yielder|
          calls << { metadata: call.metadata, deadline: call.deadline }
          current_handler.call(requests.each, yielder)
        end
      end
    end
  end

  subject(:result) { described_class.new(params, user: user, env: env).execute }

  around do |example|
    port
    grpc_server.handle(fake_service)
    server_thread = Thread.new { grpc_server.run }
    grpc_server.wait_till_running(5)
    Analytics::KnowledgeGraph::GrpcClient.clear_stubs!

    example.run
  ensure
    Analytics::KnowledgeGraph::GrpcClient.clear_stubs!
    grpc_server.stop
    server_thread&.join(5)
  end

  def result_message(result_json, query_type: 'search', row_count: 1)
    ::Orbit::V1::ExecuteQueryMessage.new(
      result: ::Orbit::V1::ExecuteQueryResult.new(
        result_json: result_json,
        metadata: ::Orbit::V1::QueryMetadata.new(
          query_type: query_type, row_count: row_count, raw_query_strings: ['SELECT 1']
        )
      )
    )
  end

  def chunk_message(data)
    ::Orbit::V1::ExecuteQueryMessage.new(result_chunk: ::Orbit::V1::ResultChunk.new(data: data))
  end

  def metadata_message
    ::Orbit::V1::ExecuteQueryMessage.new(
      result: ::Orbit::V1::ExecuteQueryResult.new(
        metadata: ::Orbit::V1::QueryMetadata.new(query_type: 'search', row_count: 1, raw_query_strings: ['SELECT 1'])
      )
    )
  end

  def text_message(text)
    ::Orbit::V1::ExecuteQueryMessage.new(result: ::Orbit::V1::ExecuteQueryResult.new(formatted_text: text))
  end

  def error_message(code, message)
    ::Orbit::V1::ExecuteQueryMessage.new(error: ::Orbit::V1::ExecuteQueryError.new(code: code, message: message))
  end

  def redaction_message(*resources)
    ::Orbit::V1::ExecuteQueryMessage.new(
      redaction: ::Orbit::V1::RedactionExchange.new(
        required: ::Orbit::V1::RedactionRequired.new(
          result_id: 'r1',
          resources: resources.map { |resource| ::Orbit::V1::ResourceToAuthorize.new(**resource) }
        )
      )
    )
  end

  def credits_exhausted_metadata
    status_details_metadata(
      ::Google::Rpc::ErrorInfo.new(reason: described_class::REASON_CREDITS_EXHAUSTED, domain: 'gitlab.com')
    )
  end

  def status_details_metadata(detail)
    status = ::Google::Rpc::Status.new(
      code: GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED,
      message: 'credits exhausted',
      details: [::Google::Protobuf::Any.pack(detail)]
    )
    { 'grpc-status-details-bin' => ::Google::Rpc::Status.encode(status) }
  end

  def stub_call(call, &run_batch)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:channel)
      .and_return(instance_double(GRPC::Core::Channel, create_call: call))
    allow(call).to receive(:run_batch, &run_batch)
  end

  def batch_result(message: nil)
    Struct::BatchResult.new.tap { |batch| batch.message = message }
  end

  def project_resource
    { resource_type: 'project', resource_ids: [readable_project.id, hidden_project.id], abilities: ['read_project'] }
  end

  def echo_authorizations(reply)
    reply.redaction.response.authorizations.to_h { |auth| [auth.resource_type, auth.authorized.to_h] }.to_json
  end

  def parsed_body
    Gitlab::Json::SafeParser.parse(result.body)
  end

  context 'with the data renderer' do
    subject(:result) do
      described_class.new(params, user: user, env: env, renderer: described_class::DataRenderer.new).execute
    end

    it 'returns the parsed result as data', :aggregate_failures do
      expect(result.body).to eq('query_type' => 'search')
      expect(result.error_code).to be_nil
    end

    context 'with the llm format' do
      let(:extra_params) { { 'Format' => 'llm' } }
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << text_message('toon text')
        end
      end

      it 'returns the formatted text' do
        expect(result.body).to eq('toon text')
      end
    end

    context 'with a chunked result' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << chunk_message('{"a":')
          yielder << chunk_message('1}')
          yielder << metadata_message
        end
      end

      it 'buffers the chunks into the data', :aggregate_failures do
        expect(result.body).to eq('a' => 1)
        expect(result.error_code).to be_nil
      end
    end

    context 'when the client disconnects after a chunk' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << chunk_message('{"a":')
          raise GRPC::Internal, 'boom'
        end
      end

      before do
        allow(Analytics::KnowledgeGraph::DisconnectWatcher).to receive(:watch) do |_socket, call|
          Analytics::KnowledgeGraph::DisconnectWatcher::Watch.new(nil, call, true)
        end
      end

      it 'returns the client closed status without tracking an exception', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
        expect(result.status).to eq(described_class::CLIENT_CLOSED_STATUS)
      end
    end

    context 'with an Orbit error message' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << error_message('timeout', 'too slow')
        end
      end

      it 'returns the error code' do
        expect(result.error_code).to eq('timeout')
      end
    end

    context 'with an unmapped Orbit error code' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << error_message('compile_error', 'bad query')
        end
      end

      it 'returns execution_error from the server reply', :aggregate_failures do
        expect(result.error_code).to eq('execution_error')
        expect(server_calls.size).to eq(1)
      end
    end

    context 'when the result is not valid JSON' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << result_message('{not json')
        end
      end

      it 'returns execution_error from the server reply', :aggregate_failures do
        expect(result.error_code).to eq('execution_error')
        expect(server_calls.size).to eq(1)
      end
    end

    context 'with an Orbit error message after a chunk' do
      using RSpec::Parameterized::TableSyntax

      where(:code, :expected) do
        'timeout'         | 'timeout'
        'quota_exhausted' | 'quota_exhausted'
        'compile_error'   | 'execution_error'
      end

      with_them do
        let(:handler) do
          ->(requests, yielder) do
            requests.next
            yielder << chunk_message('{"a":')
            yielder << error_message(code, 'failed')
          end
        end

        it 'maps the code without tracking an exception', :aggregate_failures do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
          expect(result.error_code).to eq(expected)
          expect(server_calls.size).to eq(1)
        end
      end
    end

    context 'when the stream ends after a chunk' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << chunk_message('{"a":')
        end
      end

      it 'returns execution_error without tracking an exception', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
        expect(result.error_code).to eq('execution_error')
      end
    end

    context 'when the deadline passes after a chunk' do
      let(:extra_params) { { 'TimeoutSeconds' => 1 } }
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << chunk_message('{"a":')
          sleep 3
          yielder << metadata_message
        end
      end

      it 'returns timeout without tracking an exception', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
        expect(result.error_code).to eq('timeout')
        expect(server_calls.size).to eq(1)
      end
    end

    context 'when the call times out before it starts' do
      before do
        allow_next_instance_of(described_class) { |runner| allow(runner).to receive(:timeout_seconds).and_return(0) }
      end

      it 'returns timeout' do
        expect(result.error_code).to eq('timeout')
      end
    end
  end

  context 'with a raw result' do
    it 'returns the JSON envelope with the result spliced in', :aggregate_failures do
      expect(result.status).to eq(200)
      expect(result.content_type).to eq('application/json')
      expect(result.body).to end_with("\n")
      expect(parsed_body).to eq(
        'result' => { 'query_type' => 'search' },
        'query_type' => 'search',
        'raw_query_strings' => ['SELECT 1'],
        'row_count' => 1
      )
    end
  end

  context 'with an empty result and no query strings' do
    let(:handler) do
      ->(requests, yielder) do
        requests.next
        yielder << ::Orbit::V1::ExecuteQueryMessage.new(
          result: ::Orbit::V1::ExecuteQueryResult.new(
            metadata: ::Orbit::V1::QueryMetadata.new(query_type: 'search', row_count: 0)
          )
        )
      end
    end

    it 'returns an empty result and omits the query strings' do
      expect(parsed_body).to eq('result' => '', 'query_type' => 'search', 'row_count' => 0)
    end
  end

  context 'with a chunked result' do
    using RSpec::Parameterized::TableSyntax

    let(:chunks) { ['{"a":"back\\', "\\ \"quoted\" é \u{1F600} ", " end\"}"] }
    let(:sends_chunks) { [false, true] }
    let(:requests_seen) { [] }
    let(:handler) do
      ->(requests, yielder) do
        requests_seen << requests.next.request
        next yielder << whole_message unless sends_chunks.shift

        chunks.each { |chunk| yielder << chunk_message(chunk) }
        yielder << metadata_message
      end
    end

    def whole_message
      text = chunks.join
      described_class::PROTO_FORMATS.key?(params['Format']) ? text_message(text) : result_message(text)
    end

    def run_query
      described_class.new(params, user: user, env: env).execute
    end

    def read_stream(response)
      response.body.enum_for(:each).to_a.join
    ensure
      response.body.close
    end

    where(:format, :mcp_id) do
      'raw' | nil
      'llm' | nil
      'raw' | 'mcp-1'
      'llm' | 'mcp-1'
    end

    with_them do
      let(:extra_params) { { 'Format' => format, 'McpId' => mcp_id }.compact }

      it 'streams the same status, type, and bytes as one result', :aggregate_failures do
        buffered = run_query
        streamed = run_query

        expect(streamed.status).to eq(buffered.status)
        expect(streamed.content_type).to eq(buffered.content_type)
        expect(buffered.body).to be_a(String)
        expect(read_stream(streamed)).to eq(buffered.body)
        expect(requests_seen.map(&:chunked_result)).to match_array([true, true])
      end
    end

    context 'when the stream ends' do
      let(:sends_chunks) { [true] }

      it 'records the call as ok after the last chunk' do
        expect(Gitlab::Metrics::KnowledgeGraph::Request).to receive(:observe_grpc_duration)
          .with('execute_query', 'ok', kind_of(Numeric))

        read_stream(run_query)
      end
    end

    context 'when the stream fails after a chunk' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << chunk_message('{"partial":')
          yielder << after_chunk if after_chunk
          raise GRPC::Internal, 'boom'
        end
      end

      where(:after_chunk, :logged) do
        nil               | '13: boom'
        ref(:orbit_error) | 'execution_error: ClickHouse failed'
      end

      with_them do
        let(:orbit_error) { error_message('execution_error', 'ClickHouse failed') }

        let(:logger) { instance_double(Gitlab::KnowledgeGraph::Logger, error: nil) }

        it 'logs the cause, breaks the connection, and records an error', :aggregate_failures do
          allow(Gitlab::KnowledgeGraph::Logger).to receive(:build).and_return(logger)
          expect(Gitlab::Metrics::KnowledgeGraph::Request).to receive(:observe_grpc_duration)
            .with('execute_query', 'error', kind_of(Numeric))

          expect { read_stream(run_query) }.to raise_error(described_class::StreamAborted)
          expect(logger).to have_received(:error).with(hash_including(Labkit::Fields::ERROR_MESSAGE => logged))
        end
      end

      context 'when the client has disconnected' do
        let(:after_chunk) { nil }
        let(:logger) { instance_double(Gitlab::KnowledgeGraph::Logger, error: nil) }

        before do
          allow(Analytics::KnowledgeGraph::DisconnectWatcher).to receive(:watch) do |_socket, call|
            Analytics::KnowledgeGraph::DisconnectWatcher::Watch.new(nil, call, true)
          end
        end

        it 'records a cancelled call without an error log', :aggregate_failures do
          allow(Gitlab::KnowledgeGraph::Logger).to receive(:build).and_return(logger)
          expect(Gitlab::Metrics::KnowledgeGraph::Request).to receive(:observe_grpc_duration)
            .with('execute_query', 'cancelled', kind_of(Numeric))

          expect { read_stream(run_query) }.to raise_error(described_class::StreamAborted)
          expect(logger).not_to have_received(:error)
        end
      end
    end

    context 'when reading the next chunk fails' do
      let(:call) { instance_double(GRPC::Core::Call, cancel: nil, close: nil) }
      let(:logger) { instance_double(Gitlab::KnowledgeGraph::Logger, error: nil) }
      let(:next_batch) { -> { batch_result(message: redaction_message.to_proto) } }

      before do
        allow(Gitlab::KnowledgeGraph::Logger).to receive(:build).and_return(logger)
        stub_call(call) do |ops|
          next batch_result unless ops.key?(GRPC::Core::CallOps::RECV_MESSAGE)

          first = ops.key?(GRPC::Core::CallOps::RECV_INITIAL_METADATA)
          next batch_result(message: chunk_message('{"a":').to_proto) if first

          next_batch.call
        end
      end

      def expect_logged_failure(message)
        expect { read_stream(run_query) }.to raise_error(described_class::StreamAborted)
        expect(logger).to have_received(:error).with(hash_including(Labkit::Fields::ERROR_MESSAGE => message))
      end

      it 'logs an unexpected message type' do
        expect_logged_failure(':redaction')
      end

      context 'when the call fails' do
        let(:next_batch) { -> { raise GRPC::Core::CallError, 'stream reset' } }

        it 'logs the call error' do
          expect_logged_failure('stream reset')
        end
      end

      context 'when the message does not decode' do
        let(:next_batch) { -> { batch_result(message: "\xFF") } }

        it 'tracks the exception and logs it', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(kind_of(Google::Protobuf::ParseError), user_id: user.id)

          expect_logged_failure(kind_of(String))
        end
      end
    end
  end

  context 'with a named GQL query' do
    let(:extra_params) { { 'QueryType' => 'named', 'Language' => 'gql' } }
    let(:handler) do
      ->(requests, yielder) do
        request = requests.next.request
        yielder << result_message({ query_type: request.query_type, language: request.language }.to_json)
      end
    end

    it 'sends the query type and language to the server' do
      expect(parsed_body['result']).to eq('query_type' => 'QUERY_TYPE_NAMED', 'language' => 'QUERY_LANGUAGE_GQL')
    end
  end

  context 'with projects to redact' do
    let_it_be(:member) { create(:user) }
    let_it_be(:readable_project) { create(:project, :private, reporters: member) }
    let_it_be(:hidden_project) { create(:project, :private) }

    let(:user) { member }

    context 'with a redaction exchange' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << redaction_message(project_resource)
          yielder << result_message(echo_authorizations(requests.next))
        end
      end

      it 'authorizes the resources for the user with the redaction service', :aggregate_failures do
        expect(Authz::RedactionService).to receive(:new)
          .with(hash_including(user: user, source: described_class::REDACTION_SOURCE)).and_call_original

        expect(result.status).to eq(200)
        expect(parsed_body['result']).to eq(
          'project' => { readable_project.id.to_s => true, hidden_project.id.to_s => false }
        )
      end
    end

    it 'marks the request as IO bound' do
      calls = 0
      env['puma.mark_as_io_bound'] = -> { calls += 1 }

      result

      expect(calls).to be >= 1
    end

    context 'with a group IP restriction' do
      let_it_be(:restricted_group) do
        create(:group, :public).tap { |group| create(:ip_restriction, group: group, range: '10.0.0.0/24') }
      end

      let_it_be(:restricted_project) { create(:project, :public, group: restricted_group) }

      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << redaction_message(
            { resource_type: 'project', resource_ids: [restricted_project.id], abilities: ['read_project'] }
          )
          yielder << result_message(echo_authorizations(requests.next))
        end
      end

      before do
        stub_licensed_features(group_ip_restriction: true)
      end

      def authorized_from(client_ip)
        ::Gitlab::IpAddressState.with(client_ip) { result }
        parsed_body.dig('result', 'project', restricted_project.id.to_s)
      end

      it 'redacts the resource when the request IP is outside the allowed range' do
        expect(authorized_from('192.168.1.1')).to be(false)
      end

      it 'authorizes the resource when the request IP is inside the allowed range' do
        expect(authorized_from('10.0.0.5')).to be(true)
      end
    end

    context 'with a duplicate resource_type in one redaction request' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << redaction_message(project_resource, project_resource)
          yielder << result_message(echo_authorizations(requests.next))
        end
      end

      it 'fails closed with 502', :aggregate_failures do
        expect(Authz::RedactionService).not_to receive(:new)

        expect(result.status).to eq(502)
        expect(result.content_type).to eq(described_class::TEXT_TYPE)
      end
    end
  end

  context 'with the llm format' do
    let(:extra_params) { { 'Format' => 'llm' } }
    let(:handler) { ->(requests, yielder) { yielder << text_message("format=#{requests.next.request.format}") } }

    it 'returns the formatted text as plain text', :aggregate_failures do
      expect(result.status).to eq(200)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
      expect(result.body).to eq('format=RESPONSE_FORMAT_LLM')
    end

    context 'with an MCP request id' do
      let(:extra_params) { { 'Format' => 'llm', 'McpId' => 'mcp-1' } }

      it 'wraps the formatted text in a JSON-RPC envelope', :aggregate_failures do
        expect(result.status).to eq(200)
        expect(result.content_type).to eq('application/json')
        expect(parsed_body).to include('jsonrpc' => '2.0', 'id' => 'mcp-1')
        expect(parsed_body['result']).to eq(
          'content' => [{ 'type' => 'text', 'text' => 'format=RESPONSE_FORMAT_LLM' }], 'isError' => false
        )
      end
    end
  end

  context 'with a redaction message that requires nothing' do
    let(:replies) { Queue.new }
    let(:handler) do
      received = replies
      ->(requests, yielder) do
        requests.next
        yielder << ::Orbit::V1::ExecuteQueryMessage.new(redaction: ::Orbit::V1::RedactionExchange.new)
        yielder << result_message('[]')
        received << begin
          requests.next
        rescue StopIteration
          :none
        end
      end
    end

    it 'sends no reply and returns the result', :aggregate_failures do
      expect(Authz::RedactionService).not_to receive(:new)

      expect(result.status).to eq(200)
      expect(parsed_body['result']).to eq([])
      expect(replies.pop(timeout: 2)).to eq(:none)
    end
  end

  context 'when the server sends only messages without a result' do
    let(:handler) do
      ->(requests, yielder) do
        requests.next
        (described_class::MAX_STREAM_MESSAGES + 1).times { yielder << ::Orbit::V1::ExecuteQueryMessage.new }
      end
    end

    it 'stops reading after the message limit and returns 502', :aggregate_failures do
      expect(result.status).to eq(502)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
    end
  end

  context 'with an MCP request id' do
    let(:extra_params) { { 'McpId' => 'mcp-1' } }

    it 'wraps the result in a JSON-RPC envelope', :aggregate_failures do
      expect(result.status).to eq(200)
      expect(result.content_type).to eq('application/json')
      expect(parsed_body).to include('jsonrpc' => '2.0', 'id' => 'mcp-1')
      expect(parsed_body.dig('result', 'isError')).to be(false)
      expect(result.error_reason).to be_nil
      text = parsed_body.dig('result', 'content', 0, 'text')
      expect(Gitlab::Json::SafeParser.parse(text)).to include('row_count' => 1)
    end

    context 'when the query fails' do
      let(:handler) { ->(_requests, yielder) { yielder << error_message('compile_error', 'bad query') } }

      it 'returns a tool error with HTTP 200', :aggregate_failures do
        expect(result.status).to eq(200)
        expect(parsed_body.dig('result', 'isError')).to be(true)
        expect(parsed_body.dig('result', 'content', 0, 'text')).to eq('bad query')
        expect(result.error_reason).to eq(:bad_request)
      end
    end
  end

  context 'with an Orbit error message' do
    using RSpec::Parameterized::TableSyntax

    let(:handler) do
      code = error_code
      ->(requests, yielder) do
        requests.next
        yielder << error_message(code, 'query failed')
      end
    end

    where(:error_code, :http_status) do
      'compile_error'   | 400
      'timeout'         | 504
      'execution_error' | 502
    end

    with_them do
      it 'maps the code to the HTTP status', :aggregate_failures do
        expect(result.status).to eq(http_status)
        expect(result.content_type).to eq('application/json')
        expect(parsed_body).to eq('code' => error_code, 'message' => 'query failed')
      end
    end
  end

  context 'when the server ends the stream with a gRPC status' do
    let(:grpc_code) { GRPC::Core::StatusCodes::INVALID_ARGUMENT }
    let(:handler) do
      ->(requests, _yielder) do
        requests.next
        raise GRPC::BadStatus.new(grpc_code, 'Expected ExecuteQueryRequest as first message')
      end
    end

    it 'returns the details of a client-class error', :aggregate_failures do
      expect(result.status).to eq(400)
      expect(parsed_body).to eq(
        'code' => 'invalid_request', 'message' => 'Expected ExecuteQueryRequest as first message'
      )
    end

    context 'with an MCP request' do
      let(:extra_params) { { 'McpId' => 'mcp-1' } }

      it 'returns the details as an MCP tool error', :aggregate_failures do
        expect(result.status).to eq(200)
        expect(parsed_body.dig('result', 'isError')).to be(true)
        expect(parsed_body.dig('result', 'content', 0, 'text')).to eq('Expected ExecuteQueryRequest as first message')
        expect(result.error_reason).to eq(:bad_request)
      end
    end

    context 'with a server-class error' do
      let(:grpc_code) { GRPC::Core::StatusCodes::INTERNAL }

      it 'returns a generic 502 without the details', :aggregate_failures do
        expect(result.status).to eq(502)
        expect(result.body).not_to include('Expected ExecuteQueryRequest')
      end
    end
  end

  context 'when the server is unavailable' do
    let(:handler) do
      ->(requests, _yielder) do
        requests.next
        raise GRPC::Unavailable, 'connection refused'
      end
    end

    it 'retries once and returns 502', :aggregate_failures do
      expect(result.status).to eq(502)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
      expect(server_calls.size).to eq(described_class::MAX_ATTEMPTS)
    end
  end

  context 'when the server ends the stream without a result' do
    using RSpec::Parameterized::TableSyntax

    let(:handler) do
      error = error_class&.new('stream failed', status_detail ? status_details_metadata(status_detail) : {})
      ->(requests, _yielder) do
        requests.next
        raise error if error
      end
    end

    where(:error_class, :status_detail, :http_status) do
      nil                     | nil                          | 502
      GRPC::DeadlineExceeded  | nil                          | 504
      GRPC::ResourceExhausted | nil                          | 502
      GRPC::ResourceExhausted | ::Google::Rpc::RetryInfo.new | 502
    end

    with_them do
      it 'returns a text failure', :aggregate_failures do
        expect(result.status).to eq(http_status)
        expect(result.content_type).to eq(described_class::TEXT_TYPE)
      end
    end
  end

  context 'when the server denies the query for exhausted credits' do
    let(:handler) do
      ->(requests, _yielder) do
        requests.next
        raise GRPC::BadStatus.new(
          GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED, 'credits exhausted', credits_exhausted_metadata
        )
      end
    end

    it 'returns 402 quota_exhausted', :aggregate_failures do
      expect(result.status).to eq(402)
      expect(parsed_body).to eq(
        'code' => described_class::CODE_QUOTA_EXHAUSTED,
        'message' => 'credits exhausted',
        'reason' => described_class::REASON_CREDITS_EXHAUSTED
      )
    end
  end

  context 'when the initial send fails after the server denied the query' do
    let(:call) { instance_double(GRPC::Core::Call, cancel: nil, close: nil) }

    before do
      status = GRPC::BadStatus.new(
        GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED, 'credits exhausted', credits_exhausted_metadata
      ).to_status
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:channel)
        .and_return(instance_double(GRPC::Core::Channel, create_call: call))
      allow(call).to receive(:run_batch) do |ops|
        raise GRPC::Core::CallError, 'send failed' if ops.key?(GRPC::Core::CallOps::SEND_MESSAGE)

        Struct::BatchResult.new.tap { |batch| batch.status = status }
      end
    end

    it 'reads the status and returns 402 quota_exhausted', :aggregate_failures do
      expect(result.status).to eq(402)
      expect(parsed_body).to include('code' => described_class::CODE_QUOTA_EXHAUSTED)
      expect(call).to have_received(:run_batch).with(GRPC::Core::CallOps::RECV_STATUS_ON_CLIENT => nil)
    end
  end

  context 'when the call fails after a message' do
    let(:call) { instance_double(GRPC::Core::Call, cancel: nil, close: nil) }
    let(:logger) { instance_double(Gitlab::KnowledgeGraph::Logger, error: nil) }

    before do
      allow(Gitlab::KnowledgeGraph::Logger).to receive(:build).and_return(logger)
      stub_call(call) do |ops|
        next batch_result unless ops.key?(GRPC::Core::CallOps::RECV_MESSAGE)
        raise GRPC::Core::CallError, 'stream reset' unless ops.key?(GRPC::Core::CallOps::RECV_INITIAL_METADATA)

        batch_result(message: ::Orbit::V1::ExecuteQueryMessage.new.to_proto)
      end
    end

    it 'logs the call error and returns 502', :aggregate_failures do
      expect(result.status).to eq(502)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
      expect(logger).to have_received(:error).with(hash_including(Labkit::Fields::ERROR_MESSAGE => 'stream reset'))
    end
  end

  context 'when closing the call after the result fails' do
    let(:call) { instance_double(GRPC::Core::Call, cancel: nil, close: nil) }

    before do
      stub_call(call) do |ops|
        raise GRPC::Core::CallError, 'close failed' if ops.key?(GRPC::Core::CallOps::SEND_CLOSE_FROM_CLIENT)

        batch_result(message: (result_message('[]').to_proto if ops.key?(GRPC::Core::CallOps::RECV_MESSAGE)))
      end
    end

    it 'returns the result', :aggregate_failures do
      expect(result.status).to eq(200)
      expect(parsed_body['result']).to eq([])
    end
  end

  context 'when the channel cannot be built' do
    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:channel).and_raise(ArgumentError, 'bad address')
    end

    it 'tracks the exception and returns 502', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(ArgumentError), user_id: user.id)

      expect(result.status).to eq(502)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
    end
  end

  context 'when the client has already disconnected' do
    before do
      allow(Analytics::KnowledgeGraph::DisconnectWatcher).to receive(:watch)
        .and_return(Analytics::KnowledgeGraph::DisconnectWatcher::Watch.new(nil, nil, true))
    end

    context 'when the server asks for redaction' do
      let(:handler) do
        ->(requests, yielder) do
          requests.next
          yielder << redaction_message({ resource_type: 'project', resource_ids: [1], abilities: ['read_project'] })
        end
      end

      it 'returns 499 without redacting', :aggregate_failures do
        expect(Authz::RedactionService).not_to receive(:new)

        expect(result.status).to eq(described_class::CLIENT_CLOSED_STATUS)
        expect(result.body).to eq('')
      end
    end

    context 'when the server ends the stream' do
      let(:handler) { ->(requests, _yielder) { requests.next } }

      it 'returns 499' do
        expect(result.status).to eq(described_class::CLIENT_CLOSED_STATUS)
      end
    end
  end

  context 'with request metadata' do
    let(:extra_params) do
      { 'GkgServer' => { 'address' => "127.0.0.1:#{port}", 'headers' => { 'authorization' => 'Bearer t' } } }
    end

    it 'sends the base metadata and the forwarded headers' do
      Labkit::Correlation::CorrelationId.use_id('orbit-cid') { result }

      expect(server_calls.pop[:metadata]).to include(
        'client_name' => 'gitlab-web', 'x-gitlab-correlation-id' => 'orbit-cid', 'authorization' => 'Bearer t'
      )
    end
  end

  context 'with a Rack::Timeout budget' do
    let(:extra_params) { { 'TimeoutSeconds' => 30 } }

    it 'caps the deadline before the Rack::Timeout deadline' do
      env[::Rack::Timeout::ENV_INFO_KEY] = ::Rack::Timeout::RequestDetails.new.tap do |info|
        info.timeout = 10
        info.service = 1
      end

      result

      expect(server_calls.pop[:deadline] - Time.current).to be_within(0.5).of(7)
    end

    it 'returns 504 without calling the server when the budget is spent', :aggregate_failures do
      env[::Rack::Timeout::ENV_INFO_KEY] = ::Rack::Timeout::RequestDetails.new.tap do |info|
        info.timeout = 2
        info.service = 1
      end

      expect(result.status).to eq(504)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
      expect(server_calls).to be_empty
    end

    it 'uses the query timeout without a Rack::Timeout deadline' do
      result

      expect(server_calls.pop[:deadline] - Time.current).to be_within(0.5).of(30)
    end
  end

  context 'when the client disconnects during the query' do
    let(:sockets) { UNIXSocket.pair }
    let(:env) { { 'puma.socket' => sockets.first } }
    let(:handler) do
      peer = sockets.last
      ->(requests, _yielder) do
        requests.next
        peer.close
        requests.next
      end
    end

    after do
      sockets.each { |socket| socket.close unless socket.closed? }
    end

    it 'returns 499 with an empty body', :aggregate_failures do
      expect(Gitlab::Metrics::KnowledgeGraph::Request).to receive(:observe_grpc_duration)
        .with('execute_query', 'cancelled', a_kind_of(Numeric))

      expect(result.status).to eq(described_class::CLIENT_CLOSED_STATUS)
      expect(result.body).to eq('')
    end
  end

  context 'when redaction raises an unexpected error' do
    let(:handler) do
      ->(requests, yielder) do
        requests.next
        yielder << redaction_message({ resource_type: 'project', resource_ids: [1], abilities: ['read_project'] })
        requests.next
      end
    end

    before do
      allow(Authz::RedactionService).to receive(:new).and_raise(StandardError, 'boom')
    end

    it 'tracks the exception and returns 502', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(StandardError), user_id: user.id)

      expect(result.status).to eq(502)
      expect(result.content_type).to eq(described_class::TEXT_TYPE)
    end

    context 'with an MCP request id' do
      let(:extra_params) { { 'McpId' => 'mcp-1' } }

      it 'returns a tool error with HTTP 200', :aggregate_failures do
        expect(result.status).to eq(200)
        expect(parsed_body.dig('result', 'isError')).to be(true)
        expect(parsed_body.dig('result', 'content', 0, 'text')).to eq('orbit query: internal error')
        expect(result.error_reason).to eq(:error)
      end
    end
  end

  context 'when the query exceeds the deadline' do
    let(:extra_params) { { 'TimeoutSeconds' => 1 } }
    let(:handler) do
      ->(requests, yielder) do
        requests.next
        sleep 2
        yielder << result_message('[]')
      end
    end

    it 'returns 504' do
      expect(result.status).to eq(504)
    end
  end

  context 'when the request holds a database connection', :delete do
    let(:connection_state) { Queue.new }
    let(:handler) do
      owner = ActiveSupport::IsolatedExecutionState.context
      state = connection_state
      ->(requests, yielder) do
        requests.next
        state << ApplicationRecord.connection_pool.connections.any? { |c| c.in_use? && c.owner == owner }
        yielder << result_message('[]')
      end
    end

    it 'releases the connection before waiting on the stream', :aggregate_failures do
      ApplicationRecord.connection.select_value('SELECT 1')
      expect(ApplicationRecord.connection_pool.active_connection?).to be_truthy

      expect(result.status).to eq(200)
      expect(connection_state.pop).to be(false)
    end
  end

  context 'when a connection is checked out between execute and reading a streamed body', :delete do
    let(:handler) do
      ->(requests, yielder) do
        requests.next
        yielder << chunk_message('{"a":1}')
        yielder << metadata_message
      end
    end

    it 'releases the connection before the body streams', :aggregate_failures do
      response = described_class.new(params, user: user, env: env).execute
      pool = ApplicationRecord.connection_pool
      ApplicationRecord.connection.select_value('SELECT 1')
      expect(pool.active_connection?).to be_truthy

      held_while_streaming = nil
      response.body.each { held_while_streaming = pool.active_connection? if held_while_streaming.nil? }
      response.body.close

      expect(held_while_streaming).to be_falsey
    end
  end
end
