# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Cleanup::OrphanPackageFiles, feature_category: :package_registry do
  subject(:cleaner) { described_class.new(logger: logger) }

  let(:logger) { instance_double(Logger, info: nil, error: nil) }
  let(:packages_root) { Dir.mktmpdir }
  let(:lost_and_found) { File.join(packages_root, '-', 'package-lost-found') }

  let_it_be(:project) { create(:project) }
  let_it_be(:package_file) { create(:package_file, package: create(:generic_package, project: project)) }

  before do
    allow(Packages::PackageFileUploader).to receive(:root).and_return(packages_root)
  end

  after do
    FileUtils.rm_rf(packages_root)
  end

  def hashed_dir(id)
    Gitlab::HashedPath.new(root_hash: id).to_s.delete_suffix('/')
  end

  def create_dir(relative_path, file_content: 'content', mtime: 2.days.ago.to_time)
    path = File.join(packages_root, relative_path)
    FileUtils.mkdir_p(path)
    file = File.join(path, 'file.txt')
    File.write(file, file_content)
    FileUtils.touch([file, path], mtime: mtime)
    path
  end

  describe 'uploader owners' do
    # Large IDs keep a wrong root hash, such as a record ID, from matching by chance
    let_it_be(:other_project) { create(:project, id: 900_000_001) }
    let_it_be(:group) { create(:group, id: 900_000_002) }

    # Every model that mounts an uploader on the packages storage location, with its container and a record.
    # The task treats a directory as live only when its hash is a project ID or a Debian group ID.
    let_it_be(:owners) do
      project_distribution = create(:debian_project_distribution, container: other_project)
      group_distribution = create(:debian_group_distribution, container: group)
      project_component = create(:debian_project_component, distribution: project_distribution)
      group_component = create(:debian_group_component, distribution: group_distribution)

      {
        ::Packages::PackageFile =>
          [other_project, create(:package_file, package: create(:generic_package, project: other_project))],
        ::Packages::Npm::MetadataCache => [other_project, create(:npm_metadata_cache, project: other_project)],
        ::Packages::Helm::MetadataCache => [other_project, create(:helm_metadata_cache, project: other_project)],
        ::Packages::Rubygems::SpecFile => [other_project, create(:rubygems_spec_file, project: other_project)],
        ::Packages::Rpm::RepositoryFile => [other_project, create(:rpm_repository_file, project: other_project)],
        ::Packages::Nuget::Symbol =>
          [other_project, create(:nuget_symbol, package: create(:nuget_package, project: other_project))],
        ::Packages::Debian::ProjectDistribution => [other_project, project_distribution],
        ::Packages::Debian::GroupDistribution => [group, group_distribution],
        ::Packages::Debian::ProjectComponentFile =>
          [other_project, create(:debian_project_component_file, component: project_component)],
        ::Packages::Debian::GroupComponentFile =>
          [group, create(:debian_group_component_file, component: group_component)]
      }
    end

    it 'covers every model that mounts an uploader on the packages storage location', :eager_load do
      models = ApplicationRecord.descendants.reject(&:abstract_class?).select do |model|
        model.uploaders.each_value.any? { |uploader| uploader.try(:storage_location_identifier) == :packages }
      end

      expect(models.map(&:name)).to match_array(owners.keys.map(&:name))
    end

    it 'uses a project as the container of every model except the Debian group models', :aggregate_failures do
      # The task crosses off group IDs only from the Debian group distributions
      debian_group_models = [::Packages::Debian::GroupDistribution, ::Packages::Debian::GroupComponentFile]

      owners.except(*debian_group_models).each do |model, (container, _record)|
        expect(container).to be_a(Project), model.name
      end
    end

    it 'stores the files of every model under the hashed directory of its container', :aggregate_failures do
      owners.each do |model, (container, record)|
        model.uploaders.each_key do |mount|
          expect(record.public_send(mount).store_dir.to_s).to start_with(hashed_dir(container.id)), "#{model} #{mount}"
        end
      end
    end
  end

  describe '#run!' do
    let!(:live_dir) { create_dir(File.join(hashed_dir(project.id), 'packages', '1', 'files', '1')) }
    let!(:orphan_dir) { create_dir(hashed_dir(non_existing_record_id), file_content: 'a' * 10) }
    let!(:non_hashed_dir) { create_dir(File.join('tmp', 'uploads', 'aa')) }

    let(:orphan_relative_path) { hashed_dir(non_existing_record_id) }
    let(:orphan_new_path) { File.join(lost_and_found, orphan_relative_path) }
    let(:ten_bytes) { ActiveSupport::NumberHelper.number_to_human_size(10) }
    let(:failed_summary) { '1 orphaned package directories cannot be moved. See the errors above.' }

    shared_examples 'does not touch live and non hashed directories' do
      it 'keeps them in place' do
        cleaner.run!(**args)

        expect(File.exist?(live_dir)).to be(true)
        expect(File.exist?(non_hashed_dir)).to be(true)
      end
    end

    context 'with dry run' do
      let(:args) { { dry_run: true } }

      it_behaves_like 'does not touch live and non hashed directories'

      it 'does not move the orphan directory' do
        cleaner.run!(**args)

        expect(File.exist?(orphan_dir)).to be(true)
        expect(File.exist?(orphan_new_path)).to be(false)
      end

      it 'logs the orphan directory with its size and the total' do
        expect(logger).to receive(:info).with('Looking for orphaned package files to clean up. Dry run...')
        expect(logger).to receive(:info)
          .with("Can move to lost and found #{orphan_dir} -> #{orphan_new_path} (#{ten_bytes})")
        expect(logger).to receive(:info).with("Found 1 orphaned package directories, total size #{ten_bytes}")

        cleaner.run!(**args)
      end

      it 'defaults to dry run' do
        cleaner.run!

        expect(File.exist?(orphan_dir)).to be(true)
      end

      it 'does not run more queries for more orphan directories' do
        control = ActiveRecord::QueryRecorder.new { described_class.new(logger: logger).run!(**args) }

        create_dir(hashed_dir(non_existing_record_id + 1))
        create_dir(hashed_dir(non_existing_record_id + 2))

        expect { described_class.new(logger: logger).run!(**args) }.not_to exceed_query_limit(control)
      end

      context 'when the destination already exists' do
        before do
          FileUtils.mkdir_p(orphan_new_path)
        end

        it 'does not report the orphan directory as movable' do
          expect(logger).to receive(:error).with(/destination already exists/)
          expect(logger).to receive(:error).with(failed_summary)
          expect(logger).not_to receive(:info).with(/\ACan move/)

          cleaner.run!(**args)
        end
      end
    end

    context 'without dry run' do
      let(:args) { { dry_run: false } }

      it_behaves_like 'does not touch live and non hashed directories'

      it 'moves the orphan directory to lost and found' do
        cleaner.run!(**args)

        expect(File.exist?(orphan_dir)).to be(false)
        expect(File.read(File.join(orphan_new_path, 'file.txt'))).to eq('a' * 10)
      end

      it 'logs the move and the total' do
        expect(logger).to receive(:info).with('Looking for orphaned package files to clean up...')
        expect(logger).to receive(:info)
          .with("Did move to lost and found #{orphan_dir} -> #{orphan_new_path} (#{ten_bytes})")
        expect(logger).to receive(:info).with("Moved 1 orphaned package directories, total size #{ten_bytes}")

        cleaner.run!(**args)
      end

      context 'when moving the orphan directory fails' do
        before do
          allow(FileUtils).to receive(:mv).and_call_original
          allow(FileUtils).to receive(:mv).with(orphan_dir, orphan_new_path).and_raise(Errno::EACCES)
        end

        it 'logs the error and the failed count' do
          expect(logger).to receive(:error).with(/Error during move to lost and found.*EACCES/)
          expect(logger).to receive(:error).with(failed_summary)

          cleaner.run!(**args)

          expect(File.exist?(orphan_dir)).to be(true)
        end
      end

      context 'when a file disappears while a directory is measured' do
        let!(:other_orphan_dir) { create_dir(hashed_dir(non_existing_record_id + 1)) }

        before do
          allow(File).to receive(:lstat).and_call_original
          allow(File).to receive(:lstat).with(File.join(orphan_dir, 'file.txt')).and_raise(Errno::ENOENT)
        end

        it 'counts the directory as failed and still moves the others' do
          expect(logger).to receive(:error).with(/Error during move to lost and found.*ENOENT/)
          expect(logger).to receive(:error).with(failed_summary)

          cleaner.run!(**args)

          expect(File.exist?(orphan_dir)).to be(true)
          expect(File.exist?(other_orphan_dir)).to be(false)
        end
      end

      context 'when the destination already exists' do
        before do
          FileUtils.mkdir_p(orphan_new_path)
        end

        it 'does not move the orphan directory' do
          expect(logger).to receive(:error).with(/destination already exists/)
          expect(logger).to receive(:error).with(failed_summary)

          cleaner.run!(**args)

          expect(File.exist?(orphan_dir)).to be(true)
        end
      end

      context 'when a file changed in the last 24 hours' do
        before do
          nested_dir = File.join(orphan_dir, 'packages', '1', 'files', '1')
          FileUtils.mkdir_p(nested_dir)
          File.write(File.join(nested_dir, 'file.txt'), 'content')

          # Only the new file is recent, as when a package gets a file: every directory above it stays old
          old_dirs = %w[packages packages/1 packages/1/files packages/1/files/1].map { |d| File.join(orphan_dir, d) }
          FileUtils.touch([orphan_dir, *old_dirs], mtime: 2.days.ago.to_time)
        end

        it 'skips the directory' do
          expect(logger).to receive(:info).with("Skipping #{orphan_dir}: changed in the last 24 hours")

          cleaner.run!(**args)

          expect(File.exist?(orphan_dir)).to be(true)
        end
      end

      context 'when a group has Debian distributions' do
        let_it_be(:group) { create(:group) }
        let_it_be(:distribution) { create(:debian_group_distribution, container: group) }

        let!(:group_dir) { create_dir(hashed_dir(group.id)) }

        it 'keeps the directory of the group' do
          cleaner.run!(**args)

          expect(File.exist?(group_dir)).to be(true)
          expect(File.exist?(orphan_dir)).to be(false)
        end
      end

      context 'when the project has no package records' do
        let_it_be(:empty_project) { create(:project) }

        let!(:empty_project_dir) { create_dir(hashed_dir(empty_project.id)) }

        it 'keeps the directory of the project' do
          cleaner.run!(**args)

          expect(File.exist?(empty_project_dir)).to be(true)
        end
      end
    end

    context 'when there are no orphan directories' do
      before do
        FileUtils.rm_rf(orphan_dir)
      end

      it 'keeps the live directory and reports none' do
        zero_bytes = ActiveSupport::NumberHelper.number_to_human_size(0)

        expect(logger).to receive(:info).with("Found 0 orphaned package directories, total size #{zero_bytes}")

        cleaner.run!(dry_run: true)

        expect(File.exist?(live_dir)).to be(true)
      end
    end

    context 'when find writes more errors than a pipe buffer holds' do
      let(:stderr_bytes) { 1_000_000 }

      before do
        noisy_find = "head -c #{stderr_bytes} /dev/zero | tr '\\0' x >&2; exit 1"

        allow(Open3).to receive(:popen3).with('find', any_args)
          .and_wrap_original { |method, *, &block| method.call('sh', '-c', noisy_find, &block) }
      end

      it 'does not hang and logs that the scan is incomplete' do
        expect(logger).to receive(:error)
          .with(a_string_starting_with('find exited with status 1, the scan is incomplete: xxx'))

        Timeout.timeout(30) { cleaner.run!(dry_run: true) }
      end
    end

    context 'when the packages storage path is a symlink' do
      let(:link_parent) { Dir.mktmpdir }
      let(:packages_link) { File.join(link_parent, 'packages') }

      before do
        File.symlink(packages_root, packages_link)
        allow(Packages::PackageFileUploader).to receive(:root).and_return(packages_link)
      end

      after do
        FileUtils.rm_rf(link_parent)
      end

      it 'moves the orphan directory to lost and found' do
        cleaner.run!(dry_run: false)

        expect(File.exist?(orphan_dir)).to be(false)
        expect(File.exist?(orphan_new_path)).to be(true)
        expect(File.exist?(live_dir)).to be(true)
      end
    end

    context 'when the packages storage path does not exist' do
      before do
        FileUtils.rm_rf(packages_root)
      end

      it 'logs a message and returns' do
        expect(logger).to receive(:info).with(/does not exist. Nothing to do./)

        expect { cleaner.run!(dry_run: false) }.not_to raise_error
      end
    end
  end
end
