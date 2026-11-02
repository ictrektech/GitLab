# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::MlModel::CreatePackageFileService, feature_category: :mlops do
  describe '#execute' do
    let_it_be(:project, freeze: false) { create(:project) }
    let_it_be(:user, freeze: false) { create(:user) }
    let_it_be(:pipeline, freeze: false) { create(:ci_pipeline, user: user, project: project) }
    let_it_be(:model, freeze: false) { create(:ml_models, user: user, project: project) }
    let_it_be(:model_version, freeze: false) do
      create(:ml_model_versions, :with_package, model: model, version: '0.1.0')
    end

    let_it_be(:package, freeze: false) { model_version.package }

    let(:build) { instance_double(Ci::Build, pipeline: pipeline) }

    let(:file_name) { 'myfile.tar.gz.1' }
    let(:sha256) { '440e5e148a25331bbd7991575f7d54933c0ebf6cc735a18ee5066ac1381bb590' }
    let(:temp_file) { Tempfile.new("test") }
    let(:file) { UploadedFile.new(temp_file.path, sha256: sha256) }

    subject(:execute_service) { described_class.new(project, user, params).execute }

    before do
      FileUtils.touch(temp_file)
    end

    after do
      FileUtils.rm_f(temp_file)
    end

    context 'when package is nil' do
      let(:params) do
        {
          package: nil,
          file: file,
          file_name: file_name
        }
      end

      it 'does not create package file', :aggregate_failures do
        expect(execute_service).to be_nil
      end
    end

    context 'when file name has slashes' do
      let(:file_name) { 'my_dir/myfile.tar.gz.1' }

      let(:params) do
        {
          package: package,
          file: file,
          file_name: file_name,
          status: :hidden
        }
      end

      it 'url encodes the file name' do
        expect(execute_service.file_name).to eq('my_dir%2Fmyfile.tar.gz.1')
      end
    end

    context 'with existing package' do
      let(:params) do
        {
          package: package,
          file: file,
          file_name: file_name,
          status: :hidden,
          build: build
        }
      end

      it 'adds the package file and updates status and ci_build', :aggregate_failures do
        expect { execute_service }
          .to change { model_version.package.package_files.count }.by(1)
          .and change { Packages::PackageFileBuildInfo.count }.by(1)

        package = model_version.reload.package
        package_file = package.package_files.last

        expect(package.build_infos.first.pipeline).to eq(build.pipeline)
        expect(package.status).to eq('hidden')

        expect(package_file.package).to eq(package)
        expect(package_file.file_name).to eq(file_name)
        expect(package_file.size).to eq(file.size)
        expect(package_file.file_sha256).to eq(sha256)
      end
    end

    context 'when the package has files with the same name' do
      let(:file_name) { 'my_dir/model.bin' }
      let(:params) { { package: package, file: file, file_name: file_name } }

      let!(:same_name_files) { create_list(:package_file, 2, package: package, file_name: 'my_dir%2Fmodel.bin') }
      let!(:other_name_file) { create(:package_file, package: package, file_name: 'model.bin') }
      let!(:other_package_file) do
        create(:package_file, package: create(:ml_model_package, project: project), file_name: 'my_dir%2Fmodel.bin')
      end

      it 'marks the files with the same name for destruction', :aggregate_failures do
        expect { execute_service }.to change { package.installable_package_files.count }.by(-1)

        expect(same_name_files.map(&:reload)).to all(be_pending_destruction)
        expect(execute_service.reload).to be_default
        expect(other_name_file.reload).to be_default
        expect(other_package_file.reload).to be_default
        expect(package.installable_package_files.with_file_name('my_dir%2Fmodel.bin').count).to eq(1)
      end

      context 'when more older copies exist than the limit' do
        before do
          stub_const("#{described_class}::REPLACE_LIMIT", 1)
        end

        it 'marks up to the limit and leaves the rest for a later upload', :aggregate_failures do
          execute_service

          expect(same_name_files.map(&:reload).count(&:pending_destruction?)).to eq(1)
          expect(same_name_files.count(&:default?)).to eq(1)
        end

        it 'logs that the limit was reached' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            message: 'Model registry file replacement reached the limit',
            Labkit::Fields::GL_PROJECT_ID => project.id,
            package_id: package.id,
            marked_package_files_count: 1
          )

          execute_service
        end
      end

      context 'when marking the files with the same name fails' do
        let(:error) { ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout') }

        before do
          allow(Packages::PackageFile).to receive(:created_before_id).and_raise(error)
        end

        it 'tracks the error and returns the new file', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(error, Labkit::Fields::GL_PROJECT_ID => project.id, package_id: package.id)

          expect(execute_service).to be_persisted
          expect(execute_service.file_name).to eq('my_dir%2Fmodel.bin')
        end
      end

      context 'when replace_duplicate_ml_model_package_files is enabled for another project' do
        before do
          stub_feature_flags(replace_duplicate_ml_model_package_files: create(:project))
        end

        it 'keeps the files with the same name', :aggregate_failures do
          allow(Feature).to receive(:enabled?).and_call_original
          expect(Feature).to receive(:enabled?)
            .with(:replace_duplicate_ml_model_package_files, project).and_call_original

          expect { execute_service }.to change { package.installable_package_files.count }.by(1)

          expect(same_name_files.map(&:reload)).to all(be_default)
        end
      end
    end
  end
end
