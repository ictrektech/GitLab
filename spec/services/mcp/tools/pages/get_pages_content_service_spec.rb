# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Pages::GetPagesContentService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :private, group: group, developers: [user]) }

  let_it_be(:site_files) do
    {
      'public/index.html' => "<html><body>Home</body></html>\n",
      'public/docs/index.html' => "<html><body>Docs</body></html>\n",
      'public/docs/api.html' => "<html><body>API</body></html>\n",
      'public/robots.txt' => "User-agent: *\nDisallow:\n",
      'public/logo.png' => "\x89PNG\r\n\x1a\n#{"\0" * 64}".b
    }
  end

  let_it_be(:site_archive) { build_site_archive(site_files) }
  let_it_be(:deployment) { create_pages_deployment(project, site_archive, file_count: site_files.size) }

  let(:current_user) { user }
  let(:host) { "#{group.path}.example.com" }
  let(:site_url) { "http://#{host}/#{project.path}/" }
  let(:index_html) { site_files['public/index.html'] }

  before do
    stub_pages_setting(enabled: true, host: 'example.com', url: 'http://example.com', access_control: true)
  end

  def build_site_archive(files)
    Tempfile.new(['pages', '.zip']).tap do |zip|
      Zip::OutputStream.open(zip.path) do |archive|
        files.each do |name, content|
          archive.put_next_entry(name)
          archive.write(content)
        end
      end
    end
  end

  def create_pages_deployment(project, archive, file_count:, **attributes)
    build(:pages_deployment, project: project, **attributes).tap do |pages_deployment|
      pages_deployment.file = UploadedFile.new(archive.path, filename: 'pages.zip')
      pages_deployment.file_sha256 = Digest::SHA256.file(archive.path).hexdigest
      pages_deployment.file_count = file_count
      pages_deployment.save!
    end
  end

  def execute(arguments)
    service = described_class.new(name: 'get_pages_content', version: '0.1.0')
    access_token = build_stubbed(:personal_access_token, user: current_user)
    service.set_cred(current_user: current_user, access_token: access_token)
    service.execute(params: { name: 'get_pages_content', arguments: arguments })
  end

  def error_text(result)
    result[:content].first[:text]
  end

  describe 'class configuration' do
    it 'registers version 0.1.0 as read-only in the core toolset', :aggregate_failures do
      expect(described_class.available_versions).to include('0.1.0')
      expect(described_class.version_metadata('0.1.0')[:annotations]).to eq({ readOnlyHint: true })
      expect(described_class.version_metadata('0.1.0')[:toolset]).to eq(:core)
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'GitLab Pages URL to read, for example https://mygroup.gitlab.io/myproject/docs/. ' \
              'Must be served by the GitLab Pages of this instance; other hosts are not fetched.'
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
        },
        required: %w[url]
      })
    end
  end

  describe '#resolve_governance_containers' do
    let(:service) { described_class.new(name: 'get_pages_content') }

    it 'returns the project serving the URL' do
      expect(service.resolve_governance_containers({ url: site_url })).to eq([project])
    end

    it 'returns nothing for a host that is not a Pages site' do
      expect(service.resolve_governance_containers({ url: 'https://gitlab.com/gitlab-org/gitlab' })).to be_empty
    end

    it 'returns nothing for an invalid URL' do
      expect(service.resolve_governance_containers({ url: 'not a url' })).to be_empty
    end
  end

  describe '#available?' do
    let(:service) { described_class.new(name: 'get_pages_content') }

    it 'follows the mcp_get_pages_content feature flag', :aggregate_failures do
      expect(service.available?(user)).to be(true)

      stub_feature_flags(mcp_get_pages_content: false)

      expect(service.available?(user)).to be(false)
    end
  end

  describe '#execute' do
    it 'reads index.html for the site root', :aggregate_failures do
      result = execute({ url: site_url })

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq({
        url: site_url,
        path: 'public/index.html',
        project_id: project.id,
        content_type: 'text/html',
        metadata: {
          total_bytes: index_html.bytesize,
          returned: { start: 0, end: index_html.bytesize },
          truncated: false
        },
        content: index_html
      })
    end

    it 'reads index.html for a directory URL without a trailing slash' do
      result = execute({ url: "#{site_url}docs" })

      expect(result[:structuredContent][:path]).to eq('public/docs/index.html')
    end

    it 'falls back to the .html file for an extensionless URL', :aggregate_failures do
      result = execute({ url: "#{site_url}docs/api" })

      expect(result[:structuredContent][:path]).to eq('public/docs/api.html')
      expect(result[:structuredContent][:content]).to eq(site_files['public/docs/api.html'])
    end

    it 'reads a file by its exact path and reports its content type', :aggregate_failures do
      result = execute({ url: "#{site_url}robots.txt" })

      expect(result[:structuredContent][:content_type]).to eq('text/plain')
      expect(result[:structuredContent][:content]).to eq(site_files['public/robots.txt'])
    end

    it 'ignores the query string and fragment' do
      result = execute({ url: "#{site_url}docs/?v=2#top" })

      expect(result[:structuredContent][:path]).to eq('public/docs/index.html')
    end

    it 'does not issue any HTTP request' do
      expect(Gitlab::HTTP).not_to receive(:get)

      execute({ url: site_url })
    end

    context 'with a byte window' do
      it 'truncates and points at the next byte_offset', :aggregate_failures do
        result = execute({ url: site_url, byte_limit: 6 })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq('<html>')
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: index_html.bytesize,
          returned: { start: 0, end: 6 },
          truncated: true
        })
        expect(result[:structuredContent][:system_instruction]).to eq(
          "Page content truncated. Remaining: #{index_html.bytesize - 6} bytes. " \
            'Call again with {"byte_offset": 6}.'
        )
      end

      it 'continues from byte_offset to the end of the file', :aggregate_failures do
        result = execute({ url: site_url, byte_offset: 6 })

        expect(result[:structuredContent][:content]).to eq(index_html.byteslice(6..))
        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: index_html.bytesize,
          returned: { start: 6, end: index_html.bytesize },
          truncated: false
        })
      end

      it 'says the rest cannot be read when it starts past the maximum byte_offset', :aggregate_failures do
        stub_const("#{described_class}::MAX_BYTE_OFFSET", 6)

        result = execute({ url: site_url, byte_offset: 0, byte_limit: 10 })

        expect(result[:structuredContent][:metadata][:truncated]).to be(true)
        expect(result[:structuredContent][:system_instruction]).to include('cannot be read')
        expect(result[:structuredContent][:system_instruction]).not_to include('Call again with')
      end

      it 'reports an empty window when byte_offset is past the end of the file' do
        result = execute({ url: site_url, byte_offset: 1000 })

        expect(result[:structuredContent][:metadata]).to eq({
          total_bytes: index_html.bytesize,
          returned: { start: index_html.bytesize, end: index_html.bytesize },
          truncated: false
        })
      end

      it 'rejects a byte_limit above the maximum', :aggregate_failures do
        result = execute({ url: site_url, byte_limit: 1.megabyte + 1 })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to include('byte_limit is invalid')
      end

      context 'when the file is longer than the binary sample' do
        let_it_be(:long_text) { '0123456789' * 2_000 }
        let_it_be(:long_project) do
          create(:project, :public, group: group).tap do |long_project|
            create_pages_deployment(long_project, build_site_archive('public/long.txt' => long_text), file_count: 1)
          end
        end

        let(:long_url) { "http://#{host}/#{long_project.path}/long.txt" }

        it 'reads a window that starts past the sample', :aggregate_failures do
          result = execute({ url: long_url, byte_offset: 12_000, byte_limit: 10 })

          expect(result[:structuredContent][:content]).to eq(long_text.byteslice(12_000, 10))
          expect(result[:structuredContent][:metadata][:truncated]).to be(true)
        end

        it 'reads a window that crosses the end of the sample' do
          result = execute({ url: long_url, byte_offset: 7_995, byte_limit: 10 })

          expect(result[:structuredContent][:content]).to eq(long_text.byteslice(7_995, 10))
        end
      end

      describe 'end-of-stream probe' do
        let(:service) { described_class.new(name: 'get_pages_content', version: '0.1.0') }

        it 'reports no more data when the stream ends before the declared size', :aggregate_failures do
          content, more_data = service.send(:window_from, StringIO.new(''), 'abc', 0, 10)

          expect(content).to eq('abc')
          expect(more_data).to be(false)
        end

        it 'stops skipping when the stream ends early' do
          stream = StringIO.new('abc')
          service.send(:discard, stream, 10)

          expect(stream).to be_eof
        end
      end
    end

    context 'when the project uses a unique domain' do
      let_it_be(:unique_project) do
        create(:project, :public, group: group).tap do |unique_project|
          unique_project.project_setting.update!(pages_unique_domain: 'unique-site', pages_unique_domain_enabled: true)
          create_pages_deployment(unique_project, site_archive, file_count: site_files.size)
        end
      end

      it 'serves the site from the domain root', :aggregate_failures do
        result = execute({ url: 'http://unique-site.example.com/docs/' })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:project_id]).to eq(unique_project.id)
        expect(result[:structuredContent][:path]).to eq('public/docs/index.html')
      end
    end

    context 'when the site is served from a custom domain' do
      let_it_be(:pages_domain) { create(:pages_domain, project: project) }

      it 'resolves the domain to the project', :aggregate_failures do
        result = execute({ url: "https://#{pages_domain.domain}/docs/api" })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:project_id]).to eq(project.id)
        expect(result[:structuredContent][:path]).to eq('public/docs/api.html')
      end
    end

    context 'when the group also publishes a namespace homepage' do
      let_it_be(:homepage) do
        create(:project, :public, group: group, path: "#{group.path}.example.com").tap do |homepage|
          archive = build_site_archive('public/index.html' => "Homepage\n", 'public/about.html' => "About\n")
          create_pages_deployment(homepage, archive, file_count: 2)
        end
      end

      it 'serves project URLs from the project and everything else from the homepage', :aggregate_failures do
        expect(execute({ url: site_url })[:structuredContent][:project_id]).to eq(project.id)

        about = execute({ url: "http://#{host}/about" })
        expect(about[:structuredContent][:project_id]).to eq(homepage.id)
        expect(about[:structuredContent][:path]).to eq('public/about.html')
      end

      context 'for a caller who cannot read the private project' do
        let(:current_user) { create(:user) }

        it 'answers its path the same as a path that does not exist' do
          denied = execute({ url: site_url })
          made_up = execute({ url: "http://#{host}/no-such-project/" })

          expect(error_text(denied)).to eq(error_text(made_up))
        end
      end
    end

    context 'when the URL differs in case from the project path' do
      let_it_be(:mixed_case) do
        create(:project, :public, group: group, path: 'MixedCase').tap do |mixed_case|
          create_pages_deployment(mixed_case, site_archive, file_count: site_files.size)
        end
      end

      it 'matches the project the way gitlab-pages does, ignoring case', :aggregate_failures do
        result = execute({ url: "http://#{host}/mixedcase/docs/" })

        expect(result[:structuredContent][:project_id]).to eq(mixed_case.id)
        expect(result[:structuredContent][:path]).to eq('public/docs/index.html')
      end
    end

    context 'when the deployment has no root directory' do
      let_it_be(:no_root_project) do
        create(:project, :public, group: group).tap do |no_root_project|
          archive = build_site_archive(
            'public/index.html' => "Public\n",
            'build/internal-notes.txt' => "internal only\n"
          )
          create_pages_deployment(no_root_project, archive, file_count: 2, root_directory: nil)
        end
      end

      let(:no_root_url) { "http://#{host}/#{no_root_project.path}/" }

      it 'reads from the public folder, as gitlab-pages does', :aggregate_failures do
        expect(execute({ url: no_root_url })[:structuredContent][:content]).to eq("Public\n")

        outside = execute({ url: "#{no_root_url}build/internal-notes.txt" })

        expect(outside[:isError]).to be(true)
        expect(error_text(outside)).not_to include('internal only')
      end
    end

    context 'when the deployment publishes the archive root' do
      let_it_be(:archive_root_project) do
        create(:project, :public, group: group).tap do |archive_root_project|
          archive = build_site_archive('index.html' => "Root\n")
          create_pages_deployment(archive_root_project, archive, file_count: 1, root_directory: '/')
        end
      end

      it 'reads from the archive root, as gitlab-pages does' do
        result = execute({ url: "http://#{host}/#{archive_root_project.path}/" })

        expect(result[:structuredContent][:content]).to eq("Root\n")
      end
    end

    context 'when a directory and an .html file share a name' do
      let_it_be(:ambiguous_project) do
        create(:project, :public, group: group).tap do |ambiguous_project|
          archive = build_site_archive(
            'public/data.html' => "Data page\n",
            'public/data/index.html' => "Data index\n",
            'public/info.html' => "Info page\n",
            'public/info/details.html' => "Details\n",
            'public/only.html' => "Only page\n"
          )
          create_pages_deployment(ambiguous_project, archive, file_count: 5)
        end
      end

      let(:ambiguous_url) { "http://#{host}/#{ambiguous_project.path}/" }

      it 'prefers the directory index for both /data and /data/', :aggregate_failures do
        expect(execute({ url: "#{ambiguous_url}data" })[:structuredContent][:path]).to eq('public/data/index.html')
        expect(execute({ url: "#{ambiguous_url}data/" })[:structuredContent][:path]).to eq('public/data/index.html')
      end

      it 'does not fall back to the .html file for a directory without an index' do
        expect(execute({ url: "#{ambiguous_url}info" })[:isError]).to be(true)
      end

      it 'falls back to the .html file when no directory has that name' do
        expect(execute({ url: "#{ambiguous_url}only" })[:structuredContent][:path]).to eq('public/only.html')
      end

      it 'falls back to the .html file for a trailing slash when no directory has that name' do
        expect(execute({ url: "#{ambiguous_url}only/" })[:structuredContent][:path]).to eq('public/only.html')
      end
    end

    context 'when the URL path has empty or dot segments' do
      it 'cleans them the way gitlab-pages does', :aggregate_failures do
        expect(execute({ url: "#{site_url}/docs/" })[:structuredContent][:path]).to eq('public/docs/index.html')
        expect(execute({ url: "#{site_url}./docs/api" })[:structuredContent][:path]).to eq('public/docs/api.html')
      end
    end

    context 'when the deployment lives in object storage' do
      let_it_be(:remote_project) { create(:project, :public, group: group) }

      before do
        stub_pages_object_storage(::Pages::DeploymentUploader)
        create_pages_deployment(remote_project, site_archive, file_count: site_files.size)
        stub_request(:get, %r{\Ahttps://pages\.s3\.amazonaws\.com/})
          .to_return(status: 200, body: File.binread(site_archive.path))
      end

      it 'reads the file through ranged requests', :aggregate_failures do
        result = execute({ url: "http://#{host}/#{remote_project.path}/docs/" })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(site_files['public/docs/index.html'])
      end

      it 'answers that the archive is unreadable when it cannot be opened' do
        allow(::Gitlab::HttpIO).to receive(:new).and_raise(::Gitlab::HttpIO::FailedToGetChunkError)
        remote_url = "http://#{host}/#{remote_project.path}/"

        expect(error_text(execute({ url: remote_url })))
          .to eq("Could not read the Pages deployment serving '#{remote_url}'.")
      end
    end

    context 'when the file does not exist in the deployment' do
      it 'answers like a missing site', :aggregate_failures do
        result = execute({ url: "#{site_url}missing/" })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
      end
    end

    context 'when the file is binary' do
      it 'returns an error instead of the bytes', :aggregate_failures do
        result = execute({ url: "#{site_url}logo.png" })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to include("The file at '#{site_url}logo.png' is binary (")
        expect(error_text(result)).to include("Size: #{site_files['public/logo.png'].bytesize} bytes")
      end
    end

    context 'when the deployment has too many files' do
      before do
        stub_const("#{described_class}::MAX_FILE_COUNT", site_files.size - 1)
      end

      it 'refuses to read the archive', :aggregate_failures do
        result = execute({ url: site_url })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to include("has more than #{site_files.size - 1} files")
      end
    end

    context 'when the central directory is too large' do
      let(:padding) { 'x' * 60.kilobytes }
      let(:padded_url) { "http://#{host}/#{padded_project.path}/" }
      let(:crafted_url) { "http://#{host}/#{crafted_project.path}/" }

      # rubyzip reads the last 64 KB of an archive before its directory, so these
      # archives are a few hundred KB to get past that window.
      let_it_be(:padded_project) do
        create(:project, :public, group: group).tap do |padded_project|
          archive = Tempfile.new(['pages', '.zip'])
          Zip::OutputStream.open(archive.path) do |zip|
            zip.put_next_entry('public/index.html', 'x' * 60.kilobytes)
            zip.write("Padded\n")
            4.times { |i| zip.put_next_entry("public/pad-#{i}.html", 'x' * 60.kilobytes) }
          end
          create_pages_deployment(padded_project, archive, file_count: 5)
        end
      end

      let_it_be(:crafted_project) { create(:project, :public, group: group) }

      def local_header(name, data)
        [0x04034b50, 20, 0, 0, 0, 33, Zlib.crc32(data), data.bytesize, data.bytesize, name.bytesize, 0]
          .pack('VvvvvvVVVvv') + name + data
      end

      def directory_entry(name, data, comment: '')
        [0x02014b50, 20, 20, 0, 0, 0, 33, Zlib.crc32(data), data.bytesize, data.bytesize,
          name.bytesize, 0, comment.bytesize, 0, 0, 0, 0].pack('VvvvvvvVVVvvvvvVV') + name + comment
      end

      def end_record(count, size, offset, comment: '')
        [0x06054b50, 0, 0, count, count, size, offset, comment.bytesize].pack('VvvvvVVv') + comment
      end

      def deploy_bytes(bytes)
        archive = Tempfile.new(['pages', '.zip']).tap { |file| file.binmode.write(bytes) && file.flush }
        create_pages_deployment(crafted_project, archive, file_count: 1)
      end

      def padded_directory
        [directory_entry('public/index.html', "Padded\n")] +
          Array.new(4) { |i| directory_entry("public/pad-#{i}.html", '', comment: padding) }
      end

      it 'stops reading the archive', :aggregate_failures do
        stub_const("#{described_class}::MAX_CENTRAL_DIRECTORY_BYTES", 64.kilobytes)

        result = execute({ url: padded_url })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to include('central directory larger than 65536 bytes')
      end

      it 'reads the archive once the central directory fits' do
        stub_const("#{described_class}::MAX_CENTRAL_DIRECTORY_BYTES", 512.kilobytes)

        expect(execute({ url: padded_url })[:structuredContent][:content]).to eq("Padded\n")
      end

      it 'stops reading when the archive understates its directory size' do
        stub_const("#{described_class}::MAX_CENTRAL_DIRECTORY_BYTES", 64.kilobytes)
        local = local_header('public/index.html', "Padded\n")
        directory = padded_directory.join
        deploy_bytes(local + directory + end_record(5, 1.kilobyte, local.bytesize))

        expect(error_text(execute({ url: crafted_url }))).to include('central directory larger than')
      end

      # The end record describes a one-entry directory, which is what Go's archive/zip reads.
      # rubyzip 2.4 switches to the zip64 record in the comment and loads the padded one.
      it 'stops reading when a zip64 record points at a different directory' do
        stub_const("#{described_class}::MAX_CENTRAL_DIRECTORY_BYTES", 64.kilobytes)
        local = local_header('public/index.html', "Padded\n")
        padded = padded_directory.join
        single = directory_entry('public/index.html', "Padded\n")
        single_offset = local.bytesize + padded.bytesize
        zip64_record = [0x06064b50, 44, 45, 45, 0, 0, 5, 5, padded.bytesize, local.bytesize].pack('VQ<vvVVQ<Q<Q<Q<')
        locator = [0x07064b50, 0, single_offset + single.bytesize + 22, 1].pack('VVQ<V')
        deploy_bytes(local + padded + single + end_record(1, single.bytesize, single_offset,
          comment: zip64_record + locator))

        expect(error_text(execute({ url: crafted_url }))).to include('central directory larger than')
      end
    end

    context 'when the archive cannot be read' do
      before do
        allow(Zip::File).to receive(:open_buffer).and_raise(Zip::Error)
      end

      it 'returns an error', :aggregate_failures do
        result = execute({ url: site_url })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to eq("Could not read the Pages deployment serving '#{site_url}'.")
      end
    end

    context 'when the caller cannot read the project Pages' do
      let(:current_user) { create(:user) }

      it 'answers a private site exactly as it answers a missing one', :aggregate_failures do
        denied = execute({ url: site_url })
        missing = execute({ url: 'http://nobody.example.com/' })

        expect(denied[:isError]).to be(true)
        expect(error_text(denied)).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
        expect(error_text(missing)).to eq(error_text(denied))
      end
    end

    context 'when a public project is made private while its Pages access level stays enabled' do
      let_it_be(:formerly_public) do
        create(:project, :public, group: group).tap do |formerly_public|
          create_pages_deployment(formerly_public, site_archive, file_count: site_files.size)
          formerly_public.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
        end
      end

      let(:current_user) { create(:user) }

      it 'does not serve the site to a signed-in non-member', :aggregate_failures do
        expect(formerly_public.reload.project_feature.pages_access_level).to eq(ProjectFeature::ENABLED)

        result = execute({ url: "http://#{host}/#{formerly_public.path}/" })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
      end
    end

    context 'when a private project publishes its Pages for everyone' do
      let_it_be(:public_pages_project) do
        create(:project, :private, group: group).tap do |public_pages_project|
          create_pages_deployment(public_pages_project, site_archive, file_count: site_files.size)
          public_pages_project.project_feature.update!(pages_access_level: ProjectFeature::PUBLIC)
        end
      end

      let(:current_user) { create(:user) }
      let(:public_pages_url) { "http://#{host}/#{public_pages_project.path}/" }

      it 'serves the site to a non-member without the project id', :aggregate_failures do
        result = execute({ url: public_pages_url })

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent][:content]).to eq(index_html)
        expect(result[:structuredContent]).not_to have_key(:project_id)
      end

      it 'does not name the project when a file is missing', :aggregate_failures do
        result = execute({ url: "#{public_pages_url}missing/" })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).not_to include(public_pages_project.full_path)
      end
    end

    context 'when the mcp_get_pages_content feature flag is disabled' do
      before do
        stub_feature_flags(mcp_get_pages_content: false)
      end

      it 'refuses the call', :aggregate_failures do
        result = execute({ url: site_url })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to eq('Tool execution failed: The get_pages_content tool is not enabled')
      end
    end

    context 'when the host is not a Pages site of this instance' do
      it 'does not fetch it', :aggregate_failures do
        result = execute({ url: 'https://gitlab.com/gitlab-org/gitlab' })

        expect(result[:isError]).to be(true)
        expect(error_text(result)).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
      end
    end

    context 'when Pages is disabled on the instance' do
      before do
        stub_pages_setting(enabled: false)
      end

      it 'answers as a missing site' do
        result = execute({ url: site_url })

        expect(error_text(result)).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
      end
    end

    context 'when the URL is not http or https' do
      it 'returns an error' do
        result = execute({ url: "ftp://#{host}/#{project.path}/" })

        expect(error_text(result)).to include('Invalid URL format')
      end
    end

    context 'when the URL contains a path traversal sequence' do
      it 'rejects it' do
        result = execute({ url: "#{site_url}../other/index.html" })

        expect(error_text(result)).to include('path traversal')
      end
    end

    context 'when url is omitted' do
      it 'returns an error naming the requirement' do
        result = execute({})

        expect(error_text(result)).to include('url is missing')
      end
    end
  end
end
