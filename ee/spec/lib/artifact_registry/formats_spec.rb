# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Formats, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  describe '.package_class' do
    subject(:package_class) { described_class.package_class(format_name) }

    where(:format_name, :expected_class) do
      'maven' | ArtifactRegistry::MavenPackage
      'npm'   | ArtifactRegistry::NpmPackage
    end

    with_them do
      it 'returns the package value-object class for the format' do
        expect(package_class).to eq(expected_class)
      end
    end

    context 'with a format the package routes do not serve' do
      where(format_name: [nil, '', 'docker', 'oci', 'not-a-format'])

      with_them do
        it 'names the package formats' do
          expect { package_class }.to raise_error(ArgumentError, 'format must be one of: maven, npm')
        end
      end
    end

    context 'with a package format registered without a package class' do
      let(:format_name) { 'test-format' }

      before do
        test_format = described_class::Format.new(
          name: 'test-format', collection: 'packages', package_class: nil, file_class: nil
        )
        stub_const('ArtifactRegistry::Formats::REGISTRY', described_class::REGISTRY.merge('test-format' => test_format))
        stub_const('ArtifactRegistry::Formats::PACKAGE_FORMATS', %w[maven npm test-format])
      end

      it 'raises ArgumentError rather than returning nil' do
        expect { package_class }.to raise_error(ArgumentError, 'format must be one of: maven, npm, test-format')
      end
    end
  end

  describe '.file_class' do
    subject(:file_class) { described_class.file_class(format_name) }

    where(:format_name, :expected_class) do
      'maven' | ArtifactRegistry::MavenFile
      'npm'   | ArtifactRegistry::NpmFile
    end

    with_them do
      it 'returns the file value-object class for the format' do
        expect(file_class).to eq(expected_class)
      end
    end

    context 'with a format the package routes do not serve' do
      where(format_name: [nil, '', 'docker', 'oci', 'not-a-format'])

      with_them do
        it 'names the package formats' do
          expect { file_class }.to raise_error(ArgumentError, 'format must be one of: maven, npm')
        end
      end
    end

    context 'with a package format registered without a file class' do
      let(:format_name) { 'test-format' }

      before do
        test_format = described_class::Format.new(
          name: 'test-format', collection: 'packages', package_class: ArtifactRegistry::MavenPackage, file_class: nil
        )
        stub_const('ArtifactRegistry::Formats::REGISTRY', described_class::REGISTRY.merge('test-format' => test_format))
        stub_const('ArtifactRegistry::Formats::PACKAGE_FORMATS', %w[maven npm test-format])
      end

      it 'raises ArgumentError rather than returning nil' do
        expect { file_class }.to raise_error(ArgumentError, 'format must be one of: maven, npm, test-format')
      end
    end
  end

  describe '.collection' do
    subject(:collection) { described_class.collection(format_name) }

    where(:format_name, :expected_collection) do
      'maven'  | 'packages'
      'npm'    | 'packages'
      'docker' | 'images'
      'oci'    | 'images'
    end

    with_them do
      it 'returns the collection segment for the format' do
        expect(collection).to eq(expected_collection)
      end
    end

    context 'with a format no artifact route serves' do
      where(format_name: [nil, '', 'not-a-format'])

      with_them do
        it 'names every artifact format' do
          expect { collection }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
        end
      end
    end

    context 'with a format registered under neither the packages nor the images collection' do
      let(:format_name) { 'test-format' }

      before do
        test_format = described_class::Format.new(
          name: 'test-format', collection: 'package', package_class: nil, file_class: nil
        )
        stub_const('ArtifactRegistry::Formats::REGISTRY', described_class::REGISTRY.merge('test-format' => test_format))
      end

      it 'raises ArgumentError rather than returning the unknown collection' do
        expect { collection }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
      end
    end
  end
end
