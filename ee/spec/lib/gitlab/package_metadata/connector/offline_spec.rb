# frozen_string_literal: true

require "spec_helper"

RSpec.describe ::Gitlab::PackageMetadata::Connector::Offline, feature_category: :software_composition_analysis do
  using RSpec::Parameterized::TableSyntax

  shared_examples_for 'it provides correct data' do
    let(:checkpoint) do
      build(:pm_checkpoint, sequence: seq, chunk: chunk, version_format: sync_config.version_format,
        purl_type: sync_config.purl_type)
    end

    let(:paths) do
      [
        "0/0.#{file_suffix}",
        "1/0.#{file_suffix}",
        "2/0.#{file_suffix}",
        "3/0.#{file_suffix}"
      ]
    end

    subject(:data) { connector.data_after(checkpoint).to_a }

    before do
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob).with("*/*.#{file_suffix}", base: file_prefix).and_return(paths)
    end

    context "when no checkpoint is given" do
      let(:seq) { nil }
      let(:chunk) { nil }

      it 'returns every data file in sequence order' do
        is_expected.to match([
          have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 1, chunk: 0),
          have_attributes(sequence: 2, chunk: 0), have_attributes(sequence: 3, chunk: 0)
        ])
      end
    end

    context "when a checkpoint is given" do
      context "when sequence exists and chunk do not" do
        let(:seq) { 2 }
        let(:chunk) { 1 }

        it 'returns every data file from the start' do
          is_expected.to match([
            have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 1, chunk: 0),
            have_attributes(sequence: 2, chunk: 0), have_attributes(sequence: 3, chunk: 0)
          ])
        end
      end

      context "when sequence and chunk do not exist" do
        let(:seq) { 4 }
        let(:chunk) { 0 }

        it 'returns every data file from the start' do
          is_expected.to match([
            have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 1, chunk: 0),
            have_attributes(sequence: 2, chunk: 0), have_attributes(sequence: 3, chunk: 0)
          ])
        end
      end

      context "when sequence and chunk both exist" do
        let(:seq) { 1 }
        let(:chunk) { 0 }

        it 'returns only the data files after the checkpoint' do
          is_expected.to match([
            have_attributes(sequence: 2, chunk: 0), have_attributes(sequence: 3, chunk: 0)
          ])
        end
      end
    end
  end

  # The license db does not use a directory structure
  # that maps 1:1 with the purl types. Therefore,
  # we test that we correctly convert between purl type
  # and registry id used by the license db structure.
  where(:purl_type, :registry_id) do
    :composer     | "packagist"
    :conan        | "conan"
    :gem          | "rubygem"
    :golang       | "go"
    :maven        | "maven"
    :npm          | "npm"
    :nuget        | "nuget"
    :pypi         | "pypi"
    :apk          | "apk"
    :rpm          | "rpm"
    :deb          | "deb"
    'cbl-mariner' | "cbl-mariner"
    :wolfi        | "wolfi"
  end

  let(:sync_config) do
    build(:pm_sync_config, :for_offline_license_storage, version_format: version_format, purl_type: purl_type)
  end

  let(:file_prefix) { File.join(sync_config.base_uri, version_format, registry_id) }
  let(:connector) { described_class.new(sync_config) }

  subject(:data_files) { connector.data_after(checkpoint).to_a }

  with_them do
    let(:version_format) { 'v2' }
    let(:file_suffix) { 'ndjson' }

    it_behaves_like 'it provides correct data'
  end

  # A real directory tree, not a stubbed Dir.glob: the prefix the connector
  # resolves to on disk is the behaviour under test, so a stub would assert
  # itself rather than the layout.
  context 'when reading a vendored export directory' do
    let(:tmpdir) { Dir.mktmpdir }

    # CVE enrichment is the one data type synced without a purl_type.
    let(:sync_config) do
      PackageMetadata::SyncConfiguration.new('cve_enrichment', :offline, tmpdir, 'v2', nil)
    end

    subject(:data) { connector.data_after(nil).to_a }

    after do
      FileUtils.remove_entry(tmpdir)
    end

    def write_chunk(*segments)
      path = File.join(tmpdir, *segments)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{}\n")
    end

    context 'when the CVE enrichment export is mirrored verbatim' do
      before do
        write_chunk('v2', 'cve_enrichment', '0', '000000000.ndjson')
        write_chunk('v2', 'cve_enrichment', '0', '000000001.ndjson')
      end

      it 'reads the chunks nested under the data type' do
        is_expected.to match([
          have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 0, chunk: 1)
        ])
      end

      it 'lists a file removed after the listing without opening it' do
        files = connector.data_after(nil)
        File.delete(File.join(tmpdir, 'v2', 'cve_enrichment', '0', '000000001.ndjson'))

        expect(files.to_a).to match([
          have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 0, chunk: 1)
        ])
      end
    end

    context 'when the CVE enrichment export was flattened by hand' do
      before do
        write_chunk('v2', '0', '000000000.ndjson')
        write_chunk('v2', '0', '000000001.ndjson')
      end

      it 'keeps reading the chunks at the shallower prefix' do
        is_expected.to match([
          have_attributes(sequence: 0, chunk: 0), have_attributes(sequence: 0, chunk: 1)
        ])
      end
    end

    context 'when the config has a purl type' do
      let(:sync_config) do
        PackageMetadata::SyncConfiguration.new('licenses', :offline, tmpdir, 'v2', :npm)
      end

      before do
        write_chunk('v2', 'npm', '1787609092', '000000000.ndjson')
        write_chunk('v2', 'npm', 'licenses', '99', '000000000.ndjson')
      end

      it 'reads the registry directory and ignores a data type directory inside it' do
        is_expected.to match_array([have_attributes(sequence: 1787609092, chunk: 0)])
      end
    end
  end
end
