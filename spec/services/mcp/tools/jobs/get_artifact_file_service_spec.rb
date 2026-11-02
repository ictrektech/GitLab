# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Jobs::GetArtifactFileService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, developers: [user]) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  # The :artifacts trait attaches spec/fixtures/ci_build_artifacts.zip, whose entries
  # (ci_artifacts.txt, rails_sample.jpg, ...) these examples read.
  let_it_be(:job) { create(:ci_build, :success, :artifacts, pipeline: pipeline, name: 'rspec') }

  let(:current_user) { user }
  let(:text_file) { 'ci_artifacts.txt' }
  let(:text_file_content) { "CI build artifacts fixture\n" }
  let(:text_file_size) { text_file_content.bytesize }

  def execute(arguments)
    service = described_class.new(name: 'get_artifact_file', version: '0.1.0')
    access_token = build_stubbed(:personal_access_token, user: current_user)
    service.set_cred(current_user: current_user, access_token: access_token)
    service.execute(params: { name: 'get_artifact_file', arguments: arguments })
  end

  describe 'class configuration' do
    it 'registers version 0.1.0 as read-only' do
      expect(described_class.available_versions).to include('0.1.0')
      expect(described_class.version_metadata('0.1.0')[:annotations]).to eq({ readOnlyHint: true })
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'GitLab URL of the job, for example ' \
              'https://gitlab.com/gitlab-org/gitlab/-/jobs/123. ' \
              'Provide this, or project_id and job_id.'
          },
          project_id: {
            type: 'string',
            description: 'ID or full path of the project. Required if url is not provided.'
          },
          job_id: {
            type: 'integer',
            description: 'ID of the job. Required if url is not provided.'
          },
          artifact_path: {
            type: 'string',
            description: 'Path of the file inside the artifacts archive, for example coverage/index.html. ' \
              'Required when file_type is archive.'
          },
          file_type: {
            type: 'string',
            description: 'Type of artifact to read. Omit to read the zip archive collected from ' \
              'artifacts:paths. For a report stored as its own file, pass its artifacts:reports type, ' \
              'for example junit or sast; artifact_path is then not needed.'
          },
          byte_offset: {
            type: 'integer',
            minimum: 0,
            maximum: 20.megabytes,
            description: 'Byte offset to start reading the file from.'
          },
          byte_limit: {
            type: 'integer',
            minimum: 1,
            maximum: 1.megabyte,
            description: 'Maximum number of bytes to return.'
          }
        }
      })
    end
  end

  describe '#execute' do
    it 'reads a text file out of the artifacts archive', :aggregate_failures do
      result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq({
        path: text_file,
        job_id: job.id,
        metadata: {
          total_bytes: text_file_size,
          returned: { start: 0, end: text_file_size },
          truncated: false
        },
        content: text_file_content
      })
    end

    it 'reads a file nested in a directory' do
      result = execute({
        project_id: project.full_path, job_id: job.id,
        artifact_path: 'other_artifacts_0.1.2/doc_sample.txt'
      })

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent][:metadata][:total_bytes]).to eq(1314)
    end

    context 'with a byte window' do
      it 'truncates and points at the next byte_offset', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file, byte_limit: 5 })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content].bytesize).to eq(5)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: text_file_size,
          returned: { start: 0, end: 5 },
          truncated: true
        })
        expect(result[:structuredContent][:system_instruction]).to eq(
          "Artifact file truncated. Remaining: #{text_file_size - 5} bytes. " \
            'Call again with {"byte_offset": 5}.'
        )
      end

      it 'continues from byte_offset, and the windows join up to the whole file', :aggregate_failures do
        first_window = execute({
          project_id: project.full_path, job_id: job.id, artifact_path: text_file, byte_limit: 5
        })
        second_window = execute({
          project_id: project.full_path, job_id: job.id, artifact_path: text_file, byte_offset: 5
        })

        expect(second_window[:isError]).to be(false)
        expect(second_window[:structuredContent][:metadata][:returned]).to eq(
          { start: 5, end: text_file_size }
        )

        whole = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })
        expect(first_window[:structuredContent][:content] + second_window[:structuredContent][:content])
          .to eq(whole[:structuredContent][:content])
      end

      it 'reports an empty window without inflating the entry when byte_offset is past the end of the file' do
        expect(Zip::Inflater).not_to receive(:new)

        result = execute({
          project_id: project.full_path, job_id: job.id, artifact_path: text_file, byte_offset: 100
        })

        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: text_file_size,
          returned: { start: text_file_size, end: text_file_size },
          truncated: false
        })
      end

      describe 'end-of-stream probe' do
        let(:service) { described_class.new(name: 'get_artifact_file', version: '0.1.0') }

        it 'reports no more data when the stream ends before the declared size' do
          content, truncated = service.send(:window_from, StringIO.new(''), 'abc', 0, 10)

          expect(content).to eq('abc')
          expect(truncated).to be(false)
        end

        it 'reports more data when the stream continues past the window' do
          content, truncated = service.send(:window_from, StringIO.new('def'), 'abc', 0, 3)

          expect(content).to eq('abc')
          expect(truncated).to be(true)
        end
      end

      context 'when the archive lies about the entry size' do
        before do
          # rubocop:disable RSpec/AnyInstanceOf -- entries are built inside rubyzip while parsing the archive
          allow_any_instance_of(Zip::Entry).to receive(:size).and_return(1000)
          # rubocop:enable RSpec/AnyInstanceOf
        end

        it 'trusts the metadata size over the declared one', :aggregate_failures do
          result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:metadata]).to eq({
            total_bytes: text_file_size,
            returned: { start: 0, end: text_file_size },
            truncated: false
          })
        end
      end

      it 'rejects a byte_limit above the maximum' do
        result = execute({
          project_id: project.full_path, job_id: job.id, artifact_path: text_file, byte_limit: 1.megabyte + 1
        })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('byte_limit is invalid')
      end
    end

    context 'when the file is binary' do
      it 'returns an error carrying the file name, job ID, file type, and a viewing URL', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: 'rails_sample.jpg' })

        expect(result[:isError]).to be(true)
        message = result[:content].first[:text]
        expect(message).to include("Artifact file 'rails_sample.jpg' in job #{job.id} is binary (image/jpeg)")
        expect(message).to include('Size: 35255 bytes')
        expect(message).to include(
          Gitlab::Routing.url_helpers.raw_project_job_artifacts_url(project, job, path: 'rails_sample.jpg')
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end
    end

    context 'when the file does not exist in the archive' do
      it 'returns an error listing files that do exist', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: 'nope.txt' })

        expect(result[:isError]).to be(true)
        message = result[:content].first[:text]
        expect(message).to include("Artifact file 'nope.txt' not found in the artifacts archive of job #{job.id}")
        expect(message).to include(text_file)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'when the archive has no metadata' do
      let_it_be(:no_metadata_job) { create(:ci_build, :success, pipeline: pipeline) }

      before_all do
        create(:ci_job_artifact, :archive, job: no_metadata_job)
      end

      it 'still reads the file from the archive itself' do
        result = execute({ project_id: project.full_path, job_id: no_metadata_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:metadata][:total_bytes]).to eq(text_file_size)
      end

      it 'reports a missing file without a listing' do
        result = execute({ project_id: project.full_path, job_id: no_metadata_job.id, artifact_path: 'nope.txt' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).not_to include('Files in the archive include')
      end

      it 'refuses a path that is a directory, not a file' do
        result = execute({
          project_id: project.full_path, job_id: no_metadata_job.id, artifact_path: 'other_artifacts_0.1.2'
        })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('is not a regular file')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end
    end

    context 'when the archive lives in object storage' do
      let_it_be(:remote_job) { create(:ci_build, :success, pipeline: pipeline) }

      before do
        stub_artifacts_object_storage
        create(:ci_job_artifact, :archive, :remote_store, job: remote_job)
        stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/})
          .to_return(status: 200, body: File.binread(Rails.root.join('spec/fixtures/ci_build_artifacts.zip')))
      end

      it 'downloads and reads the file' do
        result = execute({ project_id: project.full_path, job_id: remote_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(text_file_content)
      end

      it 'fetches only ranged slices of a large archive', :aggregate_failures do
        zipfile = Tempfile.new(['ranged', '.zip'])
        Zip::OutputStream.open(zipfile.path) do |zos|
          zos.put_next_entry('first_small.txt')
          zos.write('needle content')
          3.times do |i|
            zos.put_next_entry("big_#{i}.bin")
            zos.write(SecureRandom.random_bytes(300.kilobytes))
          end
        end
        zip_bytes = File.binread(zipfile.path)
        big_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :remote_store, job: big_job, file_type: :archive, file_format: :zip,
          file: UploadedFile.new(zipfile.path, filename: 'ci_build_artifacts.zip'))
        zipfile.close!

        fetched = []
        stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return do |request|
          m = request.headers['Range'].to_s.match(/bytes=(\d+)-(\d+)/)
          range_start = m[1].to_i
          range_end = [m[2].to_i, zip_bytes.size - 1].min
          fetched << (range_end - range_start + 1)
          { status: 206, body: zip_bytes[range_start..range_end],
            headers: { 'Content-Range' => "bytes #{range_start}-#{range_end}/#{zip_bytes.size}" } }
        end

        result = execute({ project_id: project.full_path, job_id: big_job.id, artifact_path: 'first_small.txt' })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('needle content')
        # Central directory (tail) plus the one entry (head), never the middle.
        expect(fetched.sum).to be < zip_bytes.size / 2
      end

      # rubyzip's end-of-central-directory scan starts 64 KB back from the end, so a
      # smaller archive forces the out-of-range seek that only object storage hits.
      it 'reads an entry from an archive smaller than the central directory scan window' do
        zipfile = Tempfile.new(['small', '.zip'])
        Zip::OutputStream.open(zipfile.path) do |zos|
          zos.put_next_entry('gl-sast-report.json')
          zos.write('{"findings":[]}')
        end
        zip_bytes = File.binread(zipfile.path)
        small_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :remote_store, job: small_job, file_type: :archive, file_format: :zip,
          file: UploadedFile.new(zipfile.path, filename: 'ci_build_artifacts.zip'))
        zipfile.close!

        stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return do |request|
          m = request.headers['Range'].to_s.match(/bytes=(\d+)-(\d+)/)
          range_start = m[1].to_i
          range_end = [m[2].to_i, zip_bytes.size - 1].min
          { status: 206, body: zip_bytes[range_start..range_end],
            headers: { 'Content-Range' => "bytes #{range_start}-#{range_end}/#{zip_bytes.size}" } }
        end

        result = execute({ project_id: project.full_path, job_id: small_job.id, artifact_path: 'gl-sast-report.json' })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('{"findings":[]}')
      end

      it 'points to the download URL when an out-of-range seek escapes the central directory scan',
        :aggregate_failures do
        allow(Zip::File).to receive(:open_buffer).and_raise(Errno::EINVAL, 'new position is outside of file')

        result = execute({ project_id: project.full_path, job_id: remote_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the artifacts archive of job #{remote_job.id}")
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, remote_job)
        )
      end

      it 'points to the download URL when the archive cannot be opened', :aggregate_failures do
        allow(::Gitlab::HttpIO).to receive(:new).and_raise(::Gitlab::HttpIO::FailedToGetChunkError)

        result = execute({ project_id: project.full_path, job_id: remote_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the artifacts archive of job #{remote_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, remote_job)
        )
      end

      it 'points to the download URL when a ranged request fails', :aggregate_failures do
        stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return(status: 500)

        result = execute({ project_id: project.full_path, job_id: remote_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the artifacts archive of job #{remote_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, remote_job)
        )
      end
    end

    context 'when an entry has corrupted compressed data' do
      let_it_be(:damaged_job) { create(:ci_build, :success, pipeline: pipeline) }

      before_all do
        damaged = Tempfile.new(['damaged', '.zip'])
        Zip::OutputStream.open(damaged.path) do |zos|
          zos.put_next_entry('ci_artifacts.txt')
          zos.write('compressible ' * 2_000)
        end
        # Local header is 30 bytes plus the name; overwrite the deflate stream right after it.
        data_start = 30 + 'ci_artifacts.txt'.bytesize
        bytes = File.binread(damaged.path)
        bytes[data_start, 64] = ("\xFF" * 64).b
        File.binwrite(damaged.path, bytes)
        create(:ci_job_artifact, job: damaged_job, file_type: :archive, file_format: :zip,
          file: UploadedFile.new(damaged.path, filename: 'ci_build_artifacts.zip'))
        damaged.unlink
      end

      it 'points to the download URL', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: damaged_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the artifacts archive of job")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, damaged_job)
        )
      end
    end

    context 'when the archive is not a valid zip' do
      let_it_be(:corrupt_job) { create(:ci_build, :success, pipeline: pipeline) }

      before_all do
        corrupt = Tempfile.new(['corrupt', '.zip'])
        corrupt.write('not a zip')
        corrupt.close
        create(:ci_job_artifact, job: corrupt_job, file_type: :archive, file_format: :zip,
          file: UploadedFile.new(corrupt.path, filename: 'ci_build_artifacts.zip'))
        corrupt.unlink
      end

      it 'points to the download URL', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: corrupt_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the artifacts archive of job")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, corrupt_job)
        )
      end
    end

    context 'when the job has no artifacts archive' do
      let_it_be(:bare_job) { create(:ci_build, :success, pipeline: pipeline) }

      it 'says so' do
        result = execute({ project_id: project.full_path, job_id: bare_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Job #{bare_job.id} has no artifacts archive.")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'with a report artifact stored as its own file' do
      let_it_be(:report_job) { create(:ci_build, :success, pipeline: pipeline, name: 'report') }
      let_it_be(:sast_artifact) { create(:ci_job_artifact, :sast, job: report_job) }
      let_it_be(:junit_artifact) { create(:ci_job_artifact, :junit, job: report_job) }

      let(:sast_json) { File.read(Rails.root.join('spec/fixtures/security_reports/master/gl-sast-report.json')) }
      let(:junit_xml) do
        ActiveSupport::Gzip.decompress(File.binread(Rails.root.join('spec/fixtures/junit/junit.xml.gz')))
          .force_encoding(Encoding::UTF_8)
      end

      it 'reads a raw report without an artifact_path', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).to eq({
          path: 'gl-sast-report.json',
          job_id: report_job.id,
          metadata: {
            total_bytes: sast_json.bytesize,
            returned: { start: 0, end: sast_json.bytesize },
            truncated: false
          },
          content: sast_json
        })
      end

      it 'inflates a gzipped report' do
        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'junit' })

        expect(result[:structuredContent][:path]).to eq('junit.xml')
        expect(result[:structuredContent][:content]).to eq(junit_xml)
      end

      it 'pages through a report with a byte window', :aggregate_failures do
        result = execute({
          project_id: project.full_path, job_id: report_job.id, file_type: 'junit', byte_offset: 10, byte_limit: 20
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(junit_xml.byteslice(10, 20))
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: junit_xml.bytesize,
          returned: { start: 10, end: 30 },
          truncated: true
        })
        expect(result[:structuredContent][:system_instruction]).to eq(
          "Artifact file truncated. Remaining: #{junit_xml.bytesize - 30} bytes. " \
            'Call again with {"byte_offset": 30}.'
        )
      end

      it 'returns an empty window past the end of a raw report', :aggregate_failures do
        result = execute({
          project_id: project.full_path, job_id: report_job.id, file_type: 'sast',
          byte_offset: sast_json.bytesize + 10
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('')
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: sast_json.bytesize,
          returned: { start: sast_json.bytesize, end: sast_json.bytesize },
          truncated: false
        })
      end

      it 'returns an empty window past the end of a report', :aggregate_failures do
        result = execute({
          project_id: project.full_path, job_id: report_job.id, file_type: 'junit', byte_offset: junit_xml.bytesize + 5
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('')
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: junit_xml.bytesize,
          returned: { start: junit_xml.bytesize, end: junit_xml.bytesize },
          truncated: false
        })
      end

      it 'reads a window of a gzipped report without holding the rest in memory', :aggregate_failures do
        inflated = 'a' * 5.megabytes
        bomb_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          file.write(ActiveSupport::Gzip.compress(inflated))
          file.flush
          create(:ci_job_artifact, job: bomb_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        expect(Gitlab::Ci::Artifacts::DecompressedArtifactSizeValidator).not_to receive(:new)
        expect_next_found_instance_of(Ci::JobArtifact) { |artifact| expect(artifact).not_to receive(:each_blob) }

        result = execute({ project_id: project.full_path, job_id: bomb_job.id, file_type: 'junit', byte_limit: 16 })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('a' * 16)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: inflated.bytesize,
          returned: { start: 0, end: 16 },
          truncated: true
        })
      end

      context 'when the report lives in object storage' do
        before do
          stub_artifacts_object_storage
        end

        it 'reads a gzipped report through ranged requests', :aggregate_failures do
          inflated = 'a' * 5.megabytes
          gzip_bytes = ActiveSupport::Gzip.compress(inflated)
          remote_report_job = create(:ci_build, :success, pipeline: pipeline)
          Tempfile.create(['junit', '.xml.gz']) do |file|
            file.binmode
            file.write(gzip_bytes)
            file.flush
            create(:ci_job_artifact, :remote_store, job: remote_report_job, file_type: :junit, file_format: :gzip,
              file: UploadedFile.new(file.path, filename: 'junit.xml.gz'))
          end
          stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return do |request|
            m = request.headers['Range'].to_s.match(/bytes=(\d+)-(\d+)/)
            range_start = m[1].to_i
            range_end = [m[2].to_i, gzip_bytes.size - 1].min
            { status: 206, body: gzip_bytes[range_start..range_end],
              headers: { 'Content-Range' => "bytes #{range_start}-#{range_end}/#{gzip_bytes.size}" } }
          end

          result = execute({
            project_id: project.full_path, job_id: remote_report_job.id, file_type: 'junit', byte_limit: 16
          })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:content]).to eq('a' * 16)
          expect(result[:structuredContent][:metadata]).to eq({
            total_bytes: inflated.bytesize,
            returned: { start: 0, end: 16 },
            truncated: true
          })
        end

        it 'counts the size of a large gzipped report in one pass', :aggregate_failures do
          gzip_bytes = ActiveSupport::Gzip.compress(SecureRandom.hex(1.megabyte))
          large_remote_job = create(:ci_build, :success, pipeline: pipeline)
          Tempfile.create(['junit', '.xml.gz']) do |file|
            file.binmode
            file.write(gzip_bytes)
            file.flush
            create(:ci_job_artifact, :remote_store, job: large_remote_job, file_type: :junit, file_format: :gzip,
              file: UploadedFile.new(file.path, filename: 'junit.xml.gz'))
          end
          fetched = []
          stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return do |request|
            m = request.headers['Range'].to_s.match(/bytes=(\d+)-(\d+)/)
            range_start = m[1].to_i
            range_end = [m[2].to_i, gzip_bytes.size - 1].min
            fetched << (range_end - range_start + 1)
            { status: 206, body: gzip_bytes[range_start..range_end],
              headers: { 'Content-Range' => "bytes #{range_start}-#{range_end}/#{gzip_bytes.size}" } }
          end

          result = execute({
            project_id: project.full_path, job_id: large_remote_job.id, file_type: 'junit', byte_limit: 16
          })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:content].bytesize).to eq(16)
          expect(result[:structuredContent][:metadata]).to eq({
            total_bytes: 2.megabytes,
            returned: { start: 0, end: 16 },
            truncated: true
          })
          # The size needs the whole compressed file, but no range is fetched twice.
          expect(fetched.sum).to be <= gzip_bytes.size
        end

        it 'reports a failed ranged request as unreadable', :aggregate_failures do
          failing_job = create(:ci_build, :success, pipeline: pipeline)
          Tempfile.create(['junit', '.xml.gz']) do |file|
            file.binmode
            file.write(ActiveSupport::Gzip.compress('a' * 1000))
            file.flush
            create(:ci_job_artifact, :remote_store, job: failing_job, file_type: :junit, file_format: :gzip,
              file: UploadedFile.new(file.path, filename: 'junit.xml.gz'))
          end
          stub_request(:get, %r{\Ahttps://artifacts\.s3\.amazonaws\.com/}).to_return(status: 500)

          result = execute({ project_id: project.full_path, job_id: failing_job.id, file_type: 'junit' })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include("Could not read the junit artifact of job #{failing_job.id}")
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        end
      end

      it 'reads a multi-member gzip report as one stream', :aggregate_failures do
        multi_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          # One member per matched file, as the runner writes them. The trailer
          # describes the last member only, so the size cannot come from it.
          file.write(Zlib.gzip('x' * 5000) + Zlib.gzip('y' * 10))
          file.flush
          create(:ci_job_artifact, job: multi_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        result = execute({ project_id: project.full_path, job_id: multi_job.id, file_type: 'junit', byte_limit: 100 })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('x' * 100)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: 5010,
          returned: { start: 0, end: 100 },
          truncated: true
        })

        # A window that starts inside one member and ends in the next.
        result = execute({
          project_id: project.full_path, job_id: multi_job.id, file_type: 'junit',
          byte_offset: 4990, byte_limit: 100
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(('x' * 10) + ('y' * 10))
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: 5010,
          returned: { start: 4990, end: 5010 },
          truncated: false
        })
      end

      it 'returns every file of a report the runner collected from several files', :aggregate_failures do
        three_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :junit_with_three_testsuites, job: three_job)
        expected = %w[1 2 3].map { |n| fixture_file("junit/junit_with_three_testsuites_#{n}.xml") }.join

        result = execute({ project_id: project.full_path, job_id: three_job.id, file_type: 'junit' })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(expected)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: expected.bytesize,
          returned: { start: 0, end: expected.bytesize },
          truncated: false
        })
      end

      it 'points at the download once the next window is past the offset cap', :aggregate_failures do
        max_offset = described_class::MAX_BYTE_OFFSET
        big_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          file.write(ActiveSupport::Gzip.compress(('a' * max_offset) + ('b' * 32)))
          file.flush
          create(:ci_job_artifact, job: big_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        result = execute({
          project_id: project.full_path, job_id: big_job.id, file_type: 'junit',
          byte_offset: max_offset - 16, byte_limit: 32
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: max_offset + 32,
          returned: { start: max_offset - 16, end: max_offset + 16 },
          truncated: true
        })
        instruction = result[:structuredContent][:system_instruction]
        expect(instruction).to include("Remaining: 16 bytes, beyond the #{max_offset} bytes this tool reads.")
        expect(instruction).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, big_job, file_type: 'junit')
        )
      end

      it 'stops counting a gzipped report past the furthest window and reports a floor', :aggregate_failures do
        limit = described_class::MAX_COUNTED_BYTES
        huge_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          file.write(ActiveSupport::Gzip.compress('a' * (limit + 5.megabytes)))
          file.flush
          create(:ci_job_artifact, job: huge_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        result = execute({ project_id: project.full_path, job_id: huge_job.id, file_type: 'junit', byte_limit: 16 })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: limit,
          returned: { start: 0, end: 16 },
          truncated: true
        })
        expect(result[:structuredContent][:system_instruction]).to include("Remaining: at least #{limit - 16} bytes.")
      end

      it 'offers the offset cap itself as the next window', :aggregate_failures do
        max_offset = described_class::MAX_BYTE_OFFSET
        edge_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          file.write(ActiveSupport::Gzip.compress(('a' * max_offset) + ('b' * 16)))
          file.flush
          create(:ci_job_artifact, job: edge_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        result = execute({
          project_id: project.full_path, job_id: edge_job.id, file_type: 'junit',
          byte_offset: max_offset - 16, byte_limit: 16
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:system_instruction]).to eq(
          "Artifact file truncated. Remaining: 16 bytes. Call again with {\"byte_offset\": #{max_offset}}."
        )
      end

      it 'ignores artifact_path when a report type is requested' do
        result = execute({
          project_id: project.full_path, job_id: report_job.id, file_type: 'sast', artifact_path: 'other.json'
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:path]).to eq('gl-sast-report.json')
      end

      it 'rejects an unknown file_type', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'nope' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("file_type is not a downloadable artifact type: 'nope'")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'rejects the archive index and the job log' do
        %w[metadata trace].each do |type|
          result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: type })

          expect(result[:isError]).to be(true)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
        end
      end

      it 'requires artifact_path when reading the archive', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: job.id })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('artifact_path is required')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'says so when the job has no artifact of that type', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'codequality' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Job #{report_job.id} has no codequality artifact.")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end

      it 'names the expiry when the report is gone', :aggregate_failures do
        unlocked_pipeline = create(:ci_pipeline, :unlocked, project: project)
        expired_job = create(:ci_build, :success, pipeline: unlocked_pipeline, artifacts_expire_at: 1.day.ago)

        result = execute({ project_id: project.full_path, job_id: expired_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include(
          "Job #{expired_job.id} has no sast artifact. The artifacts have expired."
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end

      it 'treats a report the user cannot read as missing' do
        restricted_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :sast, :maintainer_only_access, job: restricted_job)

        result = execute({ project_id: project.full_path, job_id: restricted_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(true)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end

      it 'reports a report whose stored file is gone as unreadable', :aggregate_failures do
        gone_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :junit, job: gone_job)
        expect_next_found_instance_of(Ci::JobArtifact) do |artifact|
          allow(artifact.file).to receive(:open).and_return(nil)
        end

        result = execute({ project_id: project.full_path, job_id: gone_job.id, file_type: 'junit' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the junit artifact of job #{gone_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it 'reports a report whose local file is missing as unreadable', :aggregate_failures do
        gone_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, :junit, job: gone_job)
        expect_next_found_instance_of(Ci::JobArtifact) do |artifact|
          allow(artifact.file).to receive(:open).and_raise(Errno::ENOENT)
        end

        result = execute({ project_id: project.full_path, job_id: gone_job.id, file_type: 'junit' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the junit artifact of job #{gone_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it 'refuses a report larger than the cap', :aggregate_failures do
        stub_const("#{described_class}::MAX_ARCHIVE_BYTES", 100)
        expect_next_found_instance_of(Ci::JobArtifact) { |artifact| expect(artifact.file).not_to receive(:open) }

        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("is #{sast_artifact.size} bytes")
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, report_job, file_type: 'sast')
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'returns a binary report as an error pointing at the download', :aggregate_failures do
        binary_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, job: binary_job, file_type: :sast, file_format: :raw,
          file: fixture_file_upload('spec/fixtures/rails_sample.jpg', 'image/jpeg'))

        result = execute({ project_id: project.full_path, job_id: binary_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(true)
        message = result[:content].first[:text]
        expect(message).to include("Artifact file 'gl-sast-report.json' in job #{binary_job.id} is binary (image/jpeg)")
        expect(message).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, binary_job, file_type: 'sast')
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'reports a corrupt report as unreadable', :aggregate_failures do
        corrupt_job = create(:ci_build, :success, pipeline: pipeline)
        create(:ci_job_artifact, job: corrupt_job, file_type: :junit, file_format: :gzip,
          file: fixture_file_upload('spec/fixtures/rails_sample.jpg', 'application/x-gzip'))

        result = execute({ project_id: project.full_path, job_id: corrupt_job.id, file_type: 'junit' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the junit artifact of job #{corrupt_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it 'reports a report whose storage read fails as unreadable', :aggregate_failures do
        expect_next_found_instance_of(Ci::JobArtifact) do |artifact|
          allow(artifact.file).to receive(:open).and_raise(Gitlab::HttpIO::FailedToGetChunkError)
        end

        result = execute({ project_id: project.full_path, job_id: report_job.id, file_type: 'sast' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the sast artifact of job #{report_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it 'reports a file too short to be gzip as unreadable', :aggregate_failures do
        tiny_job = create(:ci_build, :success, pipeline: pipeline)
        Tempfile.create(['junit', '.xml.gz']) do |file|
          file.binmode
          file.write('ab')
          file.flush
          create(:ci_job_artifact, job: tiny_job, file_type: :junit, file_format: :gzip,
            file: fixture_file_upload(file.path, 'application/x-gzip'))
        end

        result = execute({ project_id: project.full_path, job_id: tiny_job.id, file_type: 'junit' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Could not read the junit artifact of job #{tiny_job.id}")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end

      it 'hints at file_type when artifact_path names a report and there is no archive', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: report_job.id, artifact_path: 'junit.xml' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Job #{report_job.id} has no artifacts archive.")
        expect(result[:content].first[:text]).to include('call again with {"file_type": "junit"}')
      end

      it 'hints at file_type when the archive lacks a path that names a report', :aggregate_failures do
        hinted_job = create(:ci_build, :success, :artifacts, pipeline: pipeline)
        create(:ci_job_artifact, :junit, job: hinted_job)

        result = execute({ project_id: project.full_path, job_id: hinted_job.id, artifact_path: 'junit.xml' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("not found in the artifacts archive of job #{hinted_job.id}")
        expect(result[:content].first[:text]).to include('call again with {"file_type": "junit"}')
      end

      it 'hints at file_type when artifact_path is the name get_job lists', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: report_job.id, artifact_path: 'junit.xml.gz' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Job #{report_job.id} has no artifacts archive.")
        expect(result[:content].first[:text]).to include('call again with {"file_type": "junit"}')
      end
    end

    context 'when the artifacts have expired' do
      let_it_be(:unlocked_pipeline) { create(:ci_pipeline, :unlocked, project: project) }
      let_it_be(:expired_job) do
        create(:ci_build, :success, :artifacts, pipeline: unlocked_pipeline, artifacts_expire_at: 1.day.ago)
      end

      it 'names the expiry as the reason' do
        result = execute({ project_id: project.full_path, job_id: expired_job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('The artifacts have expired.')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'when the artifacts are past expiry but kept by a locked pipeline' do
      let_it_be(:locked_pipeline) { create(:ci_pipeline, :artifacts_locked, project: project) }
      let_it_be(:locked_job) do
        create(:ci_build, :success, :artifacts, pipeline: locked_pipeline, artifacts_expire_at: 1.day.ago)
      end

      it 'still reads the file, matching the REST download endpoints' do
        result = execute({ project_id: project.full_path, job_id: locked_job.id, artifact_path: text_file })

        expect(result[:isError]).to be_falsey
        expect(result[:structuredContent][:content]).to eq(text_file_content)
      end
    end

    context 'when the archive is larger than the download cap' do
      before do
        allow_next_found_instance_of(Ci::Build) do |build|
          allow(build).to receive(:artifacts_size).and_return(described_class::MAX_ARCHIVE_BYTES + 1)
        end
      end

      it 'refuses with a pointer to the download URL', :aggregate_failures do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('exceeds')
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, job)
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end
    end

    context 'when the archive has more entries than the cap' do
      before do
        stub_const("#{described_class}::MAX_ARCHIVE_ENTRIES", 3)
      end

      it 'refuses with a pointer to the download URL, without opening the archive', :aggregate_failures do
        expect(Zip::File).not_to receive(:open)

        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('has more than 3 entries')
        expect(result[:content].first[:text]).to include(
          Gitlab::Routing.url_helpers.download_project_job_artifacts_url(project, job)
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end
    end

    describe 'job identification' do
      it 'accepts a job URL' do
        result = execute({
          url: Gitlab::Routing.url_helpers.project_job_url(project, job), artifact_path: text_file
        })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:job_id]).to eq(job.id)
      end

      it 'accepts an artifact file URL whose embedded path matches artifact_path' do
        url = "#{Gitlab::Routing.url_helpers.project_job_url(project, job)}/artifacts/file/#{text_file}"
        result = execute({ url: url, artifact_path: text_file })

        expect(result[:isError]).to be(false)
      end

      it 'rejects an artifact file URL whose embedded path contradicts artifact_path' do
        url = "#{Gitlab::Routing.url_helpers.project_job_url(project, job)}/artifacts/file/other.txt"
        result = execute({ url: url, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Artifact path mismatch')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'rejects a URL that is not a job URL' do
        result = execute({ url: "#{Gitlab.config.gitlab.url}/#{project.full_path}", artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Invalid job URL')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'rejects a non-http URL instead of crashing' do
        result = execute({ url: 'mailto:a@b.example', artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Invalid URL format')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      context 'when the instance is served under a relative URL root' do
        before do
          stub_config_setting(relative_url_root: '/gitlab')
          described_class.clear_memoization(:relative_url_root_regex)
        end

        after do
          described_class.clear_memoization(:relative_url_root_regex)
        end

        it 'strips the relative URL root from a job URL' do
          url = "#{Gitlab.config.gitlab.url}/gitlab/#{project.full_path}/-/jobs/#{job.id}"

          result = execute({ url: url, artifact_path: text_file })

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent][:job_id]).to eq(job.id)
        end
      end

      it 'does not turn a literal plus in the path into a space' do
        url = "#{Gitlab::Routing.url_helpers.project_job_url(project, job)}/artifacts/file/nope+file.txt"

        result = execute({ url: url, artifact_path: 'nope+file.txt' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('not found in the artifacts archive')
        expect(result[:content].first[:text]).not_to include('mismatch')
      end

      it 'percent-decodes the embedded artifact path before comparing' do
        url = "#{Gitlab::Routing.url_helpers.project_job_url(project, job)}/artifacts/file/" \
          'other_artifacts_0.1.2/%64oc_sample.txt'

        result = execute({ url: url, artifact_path: 'other_artifacts_0.1.2/doc_sample.txt' })

        expect(result[:isError]).to be(false)
      end

      it 'rejects url combined with project_id or job_id', :aggregate_failures do
        result = execute({
          url: Gitlab::Routing.url_helpers.project_job_url(project, job),
          project_id: project.full_path,
          artifact_path: text_file
        })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Provide either url, or project_id and job_id, not both')
      end

      it 'rejects a call with neither url nor both ids' do
        result = execute({ project_id: project.full_path, artifact_path: text_file })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Provide either url, or project_id and job_id')
      end
    end

    describe 'artifact_path validation' do
      it 'rejects a directory path' do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: 'other_artifacts_0.1.2/' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('must be a file path, not a directory')
      end

      it 'rejects a path traversal sequence' do
        result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: '../secrets.txt' })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('path traversal')
      end
    end

    describe 'authorization' do
      context 'when the job does not exist' do
        it 'returns an error that does not distinguish missing from inaccessible' do
          result = execute({ project_id: project.full_path, job_id: non_existing_record_id,
                             artifact_path: text_file })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Job not found or inaccessible')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
        end
      end

      context 'when the user cannot read the project' do
        let_it_be(:private_project) { create(:project, :private) }
        let_it_be(:private_job) do
          create(:ci_build, :artifacts, pipeline: create(:ci_pipeline, project: private_project))
        end

        let(:current_user) { create(:user) }

        it 'returns the same error as a project that does not exist' do
          result = execute({ project_id: private_project.full_path, job_id: private_job.id,
                             artifact_path: text_file })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include(
            "Project '#{private_project.full_path}' not found or inaccessible"
          )
        end
      end

      context 'when the user can read the job but not its artifacts' do
        let_it_be(:guarded_project) { create(:project, :public) }
        let_it_be(:guarded_job) do
          create(:ci_build, :success, :private_artifacts, pipeline: create(:ci_pipeline, project: guarded_project))
        end

        let(:current_user) { create(:user) }

        it 'hides whether the job exists' do
          result = execute({ project_id: guarded_project.full_path, job_id: guarded_job.id,
                             artifact_path: text_file })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Job not found or inaccessible')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end
      end

      context 'when current_user is not set' do
        let(:current_user) { nil }

        it 'returns an error' do
          result = execute({ project_id: project.full_path, job_id: job.id, artifact_path: text_file })

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('current_user is not set')
        end
      end
    end
  end

  describe 'granular token authorization' do
    let(:service) { described_class.new(name: 'get_artifact_file', version: '0.1.0') }
    let(:boundary_resource) { project }
    let(:tool_params) do
      { name: 'get_artifact_file',
        arguments: { project_id: project.full_path, job_id: job.id, artifact_path: text_file } }
    end

    it_behaves_like 'an MCP custom tool authorizing granular tokens', :download_job_artifact
  end
end
