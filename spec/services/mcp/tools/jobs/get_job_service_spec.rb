# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Jobs::GetJobService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, developers: [user]) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  describe 'class configuration' do
    it 'registers version 0.1.0 as read-only' do
      expect(described_class.available_versions).to eq(['0.1.0'])
      expect(described_class.version_metadata('0.1.0')[:annotations]).to eq({ readOnlyHint: true })
    end

    it 'aliases the old get_job_log tool name' do
      expect(described_class.tool_aliases).to eq(['get_job_log'])
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        properties: {
          id: {
            type: 'string',
            description: 'ID or full path of the project'
          },
          job_id: {
            type: 'integer',
            description: 'ID of the job'
          },
          include: {
            type: 'array',
            description: 'Facet to include alongside the job, one per call: log or artifacts.',
            items: {
              type: 'string',
              enum: %w[log artifacts]
            },
            maxItems: 1
          },
          from: {
            type: 'string',
            enum: %w[start end],
            description: 'Reads from the start of the log unless set to end. ' \
              'Cannot combine end with byte_offset. Only applies when include is log.'
          },
          byte_offset: {
            type: 'integer',
            minimum: 0,
            description: "Byte offset to start reading the job's log from. Only applies when include is log."
          },
          byte_limit: {
            type: 'integer',
            minimum: 1,
            maximum: 500.kilobytes,
            description: "Maximum number of bytes of the job's log to return; maximum is #{500.kilobytes}. " \
              'Only applies when include is log.'
          }
        },
        required: %w[id job_id]
      })
    end
  end

  describe '#execute' do
    let_it_be(:job) { create(:ci_build, :failed, pipeline: pipeline, name: 'rspec') }

    let(:current_user) { user }

    # A fresh instance per call, because the service memoizes the job it authorized.
    def execute(arguments, name: 'get_job')
      service = described_class.new(name: 'get_job', version: '0.1.0')
      access_token = build_stubbed(:personal_access_token, user: current_user)
      service.set_cred(current_user: current_user, access_token: access_token)
      service.execute(params: { name: name, arguments: arguments })
    end

    it 'returns the job metadata without the log facet', :aggregate_failures do
      result = execute({ id: project.full_path, job_id: job.id })

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq({
        id: job.id,
        name: 'rspec',
        status: 'failed',
        stage: job.stage,
        allow_failure: job.allow_failure,
        web_url: Gitlab::Routing.url_helpers.project_job_url(project, job)
      })
    end

    context 'when the job does not exist' do
      it 'returns an error that does not distinguish missing from inaccessible' do
        result = execute({ id: project.full_path, job_id: non_existing_record_id })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include(
          'Job not found or inaccessible'
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'when the project does not exist' do
      it 'returns an error' do
        result = execute({ id: 'does-not/exist', job_id: job.id })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to match(/not found or inaccessible/)
      end
    end

    context 'when the user cannot read the project' do
      let_it_be(:private_project) { create(:project, :private) }
      let_it_be(:private_job) { create(:ci_build, pipeline: create(:ci_pipeline, project: private_project)) }

      let(:current_user) { create(:user) }

      # Otherwise the distinct "Job not found" message would confirm the project exists.
      it 'returns the same error as a project that does not exist' do
        result = execute({ id: private_project.full_path, job_id: private_job.id })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include(
          "Project '#{private_project.full_path}' not found or inaccessible"
        )
      end
    end

    context 'when the user cannot read the job' do
      let_it_be(:hidden_project) { create(:project, :public, public_builds: false) }
      let_it_be(:hidden_job) { create(:ci_build, pipeline: create(:ci_pipeline, project: hidden_project)) }

      let(:current_user) { create(:user) }

      # The facet paths must not confirm the job either, or they become a way to probe for jobs.
      it 'hides whether the job exists on every path', :aggregate_failures do
        [{}, { include: %w[log] }, { include: %w[artifacts] }].each do |extra|
          result = execute({ id: hidden_project.full_path, job_id: hidden_job.id }.merge(extra))

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include(
            'Job not found or inaccessible'
          )
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end
      end
    end

    context 'when current_user is not set' do
      let(:current_user) { nil }

      it 'returns an error' do
        result = execute({ id: project.full_path, job_id: job.id })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end

    context 'with the log facet' do
      let(:job) { create(:ci_build, :trace_live, pipeline: pipeline) }

      it 'returns the whole trace when it fits in one window', :aggregate_failures do
        result = execute({ id: project.full_path, job_id: job.id, include: %w[log] })

        log = result[:structuredContent][:log]
        expect(log[:content]).to eq('BUILD TRACE')
        expect(log[:metadata]).to eq({ total_bytes: 11, returned: { start: 0, end: 11 }, truncated: false })
        expect(log).not_to have_key(:system_instruction)
      end

      context 'when the requested window does not reach the end of the trace' do
        it 'truncates and points at the next byte_offset', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], byte_limit: 5 })

          log = result[:structuredContent][:log]
          expect(log[:content]).to eq('BUILD')
          expect(log[:metadata]).to eq({ total_bytes: 11, returned: { start: 0, end: 5 }, truncated: true })
          expect(log[:system_instruction]).to eq(
            'Log truncated. Remaining: 6 bytes. Call again with {"byte_offset": 5}.'
          )
        end
      end

      context 'when byte_limit is above the maximum' do
        it 'returns a validation error' do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], byte_limit: 500.kilobytes + 1 })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('byte_limit is invalid')
        end
      end

      context 'when byte_offset is past the end of the trace' do
        it 'reports an empty window at the end of the trace' do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], byte_offset: 100 })

          expect(result[:structuredContent][:log][:metadata]).to eq(
            { total_bytes: 11, returned: { start: 11, end: 11 }, truncated: false }
          )
        end
      end

      context 'with opt-in tail reads' do
        it 'returns the tail without changing the meaning of truncated', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end', byte_limit: 5 })

          log = result[:structuredContent][:log]
          expect(log[:content]).to eq('TRACE')
          expect(log[:metadata]).to eq({ total_bytes: 11, returned: { start: 6, end: 11 }, truncated: false })
          expect(log[:system_instruction]).to eq(
            'Read earlier log bytes with {"from": "start", "byte_offset": 1, "byte_limit": 5}. ' \
              'To keep reading backwards, lower byte_offset by byte_limit each call, down to 0.'
          )
          expect(Gitlab::Json::SafeParser.parse(result[:content].first[:text])['log']).to eq(log.deep_stringify_keys)
        end

        it 'returns the whole log without continuation when the tail window is larger', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end', byte_limit: 20 })

          log = result[:structuredContent][:log]
          expect(log[:content]).to eq('BUILD TRACE')
          expect(log[:metadata]).to eq({ total_bytes: 11, returned: { start: 0, end: 11 }, truncated: false })
          expect(log).not_to have_key(:system_instruction)
        end

        it 'bounds the preceding window at the beginning of the log', :aggregate_failures do
          args = { id: project.full_path, job_id: job.id, include: %w[log], from: 'end', byte_limit: 8 }
          tail = execute(args)[:structuredContent][:log]
          continuation = Gitlab::Json::SafeParser.parse(tail[:system_instruction][/\{.*\}/]).symbolize_keys
          preceding = execute(args.merge(continuation))[:structuredContent][:log]

          expect(continuation).to eq({ from: 'start', byte_offset: 0, byte_limit: 3 })
          expect(preceding[:content] + tail[:content]).to eq('BUILD TRACE')
          expect(preceding[:metadata][:returned][:end]).to eq(tail[:metadata][:returned][:start])
        end

        it 'rejects an explicit byte_offset even when it is zero', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end', byte_offset: 0 })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('byte_offset cannot be combined with from: end')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
        end

        it 'rejects an invalid direction', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'middle' })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Invalid from')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
        end

        it 'preserves explicit forward offsets', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log],
                             from: 'start', byte_offset: 2, byte_limit: 3 })

          log = result[:structuredContent][:log]
          expect(log[:content]).to eq('ILD')
          expect(log[:metadata]).to eq({ total_bytes: 11, returned: { start: 2, end: 5 }, truncated: true })
        end

        context 'when the trace is empty' do
          let(:job) { create(:ci_build, pipeline: pipeline) }

          it 'returns an empty window without continuation', :aggregate_failures do
            result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end' })

            log = result[:structuredContent][:log]
            expect(log[:content]).to eq('')
            expect(log[:metadata]).to eq({ total_bytes: 0, returned: { start: 0, end: 0 }, truncated: false })
            expect(log).not_to have_key(:system_instruction)
          end
        end

        context 'when the tail starts inside a multi-byte character' do
          before do
            job.trace.set('✓ done')
          end

          it 'scrubs partial characters while keeping source byte offsets', :aggregate_failures do
            result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end', byte_limit: 7 })

            log = result[:structuredContent][:log]
            expect(log[:content]).to eq('�� done')
            expect(log[:metadata]).to eq({ total_bytes: 8, returned: { start: 1, end: 8 }, truncated: false })
          end
        end
      end

      context 'when the log exceeds the existing default window' do
        let(:trace) { "#{'a' * 500.kilobytes}TAIL" }

        before do
          job.trace.set(trace)
        end

        it 'keeps the start and 512000-byte default for both tool names', :aggregate_failures do
          %w[get_job get_job_log].each do |name|
            result = execute({ id: project.full_path, job_id: job.id, include: %w[log] }, name: name)

            log = result[:structuredContent][:log]
            expect(log[:content]).to eq(trace.byteslice(0, 500.kilobytes))
            expect(log[:metadata]).to eq({
              total_bytes: trace.bytesize, returned: { start: 0, end: 500.kilobytes }, truncated: true
            })
          end
        end

        it 'keeps the same default limit for an opt-in tail', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[log], from: 'end' })

          log = result[:structuredContent][:log]
          expect(log[:content]).to eq(trace.byteslice(4, 500.kilobytes))
          expect(log[:metadata]).to eq({
            total_bytes: trace.bytesize, returned: { start: 4, end: trace.bytesize }, truncated: false
          })
        end
      end

      context 'when a byte window splits a multi-byte character' do
        let(:utf8_job) { create(:ci_build, pipeline: pipeline) }

        before do
          utf8_job.trace.set('✓ done')
        end

        it 'replaces the partial character so the response can be serialized', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: utf8_job.id, include: %w[log], byte_limit: 2 })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:log][:content]).to eq('�')
        end
      end

      context 'when the job ran in debug mode' do
        let(:debug_job) do
          create(:ci_build, :trace_live, pipeline: pipeline,
            yaml_variables: [{ key: 'CI_DEBUG_TRACE', value: 'true' }])
        end

        # Reading a debug trace needs write access, so a public-build reader gets the metadata only.
        let(:current_user) { create(:user) }

        it 'returns the metadata but refuses the log', :aggregate_failures do
          expect(execute({ id: project.full_path, job_id: debug_job.id })[:isError]).to be(false)

          result = execute({ id: project.full_path, job_id: debug_job.id, include: %w[log] })

          expect(result[:isError]).to be(true)
          # The caller can already see this job, so the refusal names the reason instead of
          # claiming the job does not exist.
          expect(result[:content].first[:text]).to include(
            "Job log not accessible: you do not have permission to read this job's log."
          )
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end

        it 'also refuses opt-in tail reads', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: debug_job.id, include: %w[log], from: 'end' })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include(described_class::LOG_FORBIDDEN)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end
      end
    end

    context 'with the artifacts facet' do
      let_it_be(:job_with_artifacts) do
        create(:ci_build, :success, :artifacts, pipeline: pipeline, name: 'rspec-artifacts')
      end

      it 'lists the artifacts the job produced', :aggregate_failures do
        result = execute({ id: project.full_path, job_id: job_with_artifacts.id, include: %w[artifacts] })

        expect(result[:isError]).to be(false)

        artifacts = result[:structuredContent][:artifacts]
        expect(artifacts.map { |a| a[:file_type] }).to contain_exactly('archive', 'metadata')

        archive = job_with_artifacts.job_artifacts_archive
        expect(artifacts).to include(
          id: archive.id,
          name: archive.filename,
          size: archive.size,
          file_type: 'archive',
          expire_at: archive.expire_at,
          expired: false
        )
      end

      context 'when an artifact has expired' do
        let_it_be(:expired_artifact_job) { create(:ci_build, :success, pipeline: pipeline) }
        let_it_be(:expired_artifact) { create(:ci_job_artifact, :archive, :expired, job: expired_artifact_job) }

        it 'reports expired: true with the expiry timestamp', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: expired_artifact_job.id, include: %w[artifacts] })

          artifact = result[:structuredContent][:artifacts].find { |a| a[:id] == expired_artifact.id }
          expect(artifact[:expired]).to be(true)
          expect(artifact[:expire_at]).to eq(expired_artifact.reload.expire_at)
        end
      end

      context 'when the job has no artifacts' do
        it 'returns an empty list' do
          result = execute({ id: project.full_path, job_id: job.id, include: %w[artifacts] })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:artifacts]).to eq([])
        end
      end

      context 'when an artifact is expired' do
        let_it_be(:job_with_expired_artifact) do
          create(:ci_build, :success, pipeline: pipeline, name: 'rspec-expired')
        end

        let_it_be(:expired_artifact) { create(:ci_job_artifact, :archive, :expired, job: job_with_expired_artifact) }

        it 'reports the artifact as expired with its expiry timestamp', :aggregate_failures do
          result = execute({ id: project.full_path, job_id: job_with_expired_artifact.id, include: %w[artifacts] })

          expect(result[:isError]).to be(false), -> { result.inspect }

          artifacts = result[:structuredContent][:artifacts]
          expect(artifacts.map { |artifact| artifact[:id] }).to contain_exactly(expired_artifact.id)
          expect(artifacts.first[:expired]).to be(true)
          expect(artifacts.first[:expire_at]).to be_like_time(expired_artifact.expire_at)
        end
      end
    end

    context 'when called as the get_job_log alias' do
      let(:job) { create(:ci_build, :trace_live, pipeline: pipeline) }

      it 'returns the log without an explicit include' do
        result = execute({ id: project.full_path, job_id: job.id }, name: 'get_job_log')

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:log][:content]).to eq('BUILD TRACE')
      end

      it 'supports an explicit tail without an include parameter', :aggregate_failures do
        result = execute({ id: project.full_path, job_id: job.id, from: 'end', byte_limit: 5 }, name: 'get_job_log')

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:log][:content]).to eq('TRACE')
      end
    end
  end

  describe 'granular token authorization' do
    let_it_be(:job) { create(:ci_build, pipeline: pipeline) }

    let(:service) { described_class.new(name: 'get_job', version: '0.1.0') }
    let(:current_user) { user }
    let(:boundary_resource) { project }
    let(:tool_params) { { name: 'get_job', arguments: { id: project.full_path, job_id: job.id } } }

    it_behaves_like 'an MCP custom tool authorizing granular tokens', :read_job
  end
end
