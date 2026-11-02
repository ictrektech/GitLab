# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VirtualRegistries::Local::Upstream::File, feature_category: :virtual_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:file) { build(:virtual_registries_local_upstream_file) }

  let_it_be(:package_file) do
    create(
      :package_file,
      file_name: 'my-app-1.0.jar',
      file_md5: '09f7e02f1290be211da707a266f153b8',
      file_sha1: 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd8'
    )
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:global_id) }
    it { is_expected.to validate_presence_of(:file) }
    it { is_expected.to validate_presence_of(:file_name) }
    it { is_expected.to validate_presence_of(:sha1) }
    it { is_expected.to validate_presence_of(:md5) }

    it { is_expected.to allow_value('a94a8fe5ccb19ba61c4c0873d391e987982fbbd6').for(:sha1) }
    it { is_expected.not_to allow_value('a94a8fe5ccb19ba61c4c0873d391e987982fbbd!').for(:sha1) }
    it { is_expected.not_to allow_value('tooshort').for(:sha1) }

    it { is_expected.to allow_value('09f7e02f1290be211da707a266f153b6').for(:md5) }
    it { is_expected.not_to allow_value('09f7e02f1290be211da707a266f153b!').for(:md5) }
    it { is_expected.not_to allow_value('tooshort').for(:md5) }

    context 'in FIPS mode', :fips_mode do
      it { is_expected.to allow_value(nil).for(:md5) }
      it { is_expected.not_to allow_value('').for(:md5) }
      it { is_expected.not_to allow_value('tooshort').for(:md5) }
    end
  end

  describe '.from_raw_local_file' do
    context 'with a package file' do
      subject(:from_raw_local_file) { described_class.from_raw_local_file(package_file) }

      it 'creates the correct local file instance' do
        is_expected.to have_attributes(
          global_id: package_file.to_global_id.to_s,
          raw_file_id: package_file.id,
          file: instance_of(::Packages::PackageFileUploader),
          file_name: 'my-app-1.0.jar',
          sha1: package_file.file_sha1,
          md5: package_file.file_md5
        )
      end

      %i[md5 sha1].each do |digest_format|
        context "with invalid #{digest_format}" do
          let_it_be(:package_file) { create(:package_file, "file_#{digest_format}" => "too_short") }

          it 'raise an ArgumentError with validation errors' do
            expect { from_raw_local_file }.to raise_error(ArgumentError) do |error|
              expect(error.message).not_to be_empty
            end
          end
        end
      end

      context 'without md5' do
        let_it_be(:package_file) do
          create(:package_file, file_md5: nil, file_sha1: 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd8')
        end

        it 'raises an ArgumentError with validation errors' do
          expect { from_raw_local_file }.to raise_error(ArgumentError, "Md5 can't be blank")
        end

        context 'in FIPS mode', :fips_mode do
          it 'creates the local file instance without md5' do
            is_expected.to have_attributes(
              sha1: 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd8',
              md5: nil
            )
          end
        end
      end
    end

    context 'with a non accepted object class' do
      let_it_be(:project) { create(:project) }

      subject(:from_raw_local_file) { described_class.from_raw_local_file(project) }

      it 'raises an ArgumentError' do
        expect { from_raw_local_file }.to raise_error(ArgumentError, described_class::INVALID_RAW_FILE_TYPE_ERROR)
      end
    end
  end

  describe '#content_type' do
    subject { build(:virtual_registries_local_upstream_file, file_name:).content_type }

    where(:file_name, :expected_content_type) do
      'my-app-1.0.jar'     | 'application/java-archive'
      'maven-metadata.xml' | 'application/xml'
      'my-app-1.0.pom'     | 'application/octet-stream'
    end

    with_them do
      it { is_expected.to eq(expected_content_type) }
    end

    context 'with a file built from a package file' do
      let(:file) { described_class.from_raw_local_file(package_file) }

      it 'does not read the content type from the uploader' do
        expect(file.file).not_to receive(:content_type)

        file.content_type
      end
    end
  end

  describe 'eql?' do
    let(:file) { described_class.from_raw_local_file(package_file) }
    let(:other_file) { described_class.from_raw_local_file(package_file) }

    subject { file.eql?(other_file) }

    it { is_expected.to be_truthy }

    context 'when other is not a File instance' do
      let(:other_file) { 'not a file' }

      it { is_expected.to be_falsey }
    end
  end

  describe '#hash' do
    let(:file) { described_class.from_raw_local_file(package_file) }
    let(:other_file) { described_class.from_raw_local_file(package_file) }

    it 'returns the same hash for equal objects' do
      expect(file.hash).to eq(other_file.hash)
    end
  end

  describe '#digests' do
    let(:file) { described_class.from_raw_local_file(package_file) }

    subject { file.digests }

    it { is_expected.to eq({ sha1: package_file.file_sha1, md5: package_file.file_md5 }) }
  end
end
