# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::GitStrategy, feature_category: :duo_agent_platform do
  let(:project) { build_stubbed(:project) }
  let(:reference_repository_path) { '/opt/duo/ref.git' }

  subject(:git_strategy) do
    described_class.new(project: project, reference_repository_path: reference_repository_path)
  end

  shared_examples 'the runner clone' do
    it 'does not use the reference repository', :aggregate_failures do
      expect(git_strategy.reference_repository?).to be(false)
      expect(git_strategy.variables).to eq({})
      expect(git_strategy.clone_commands).to eq([])
    end
  end

  describe '#reference_repository?' do
    it { expect(git_strategy.reference_repository?).to be(true) }
  end

  describe '#variables' do
    it 'starts from an empty directory and passes the path to the job script' do
      expect(git_strategy.variables).to eq(
        GIT_STRATEGY: 'empty',
        GIT_LFS_SKIP_SMUDGE: 1,
        DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH: '/opt/duo/ref.git'
      )
    end
  end

  describe '#clone_commands' do
    it 'reads the path from the job variable rather than interpolating it' do
      expect(git_strategy.clone_commands.join("\n")).not_to include(reference_repository_path)
    end

    it 'does not rely on CI_COMMIT_SHA, which workload jobs do not get' do
      expect(git_strategy.clone_commands.join("\n")).not_to include('CI_COMMIT_SHA')
    end

    context 'when run against real repositories', :aggregate_failures do
      let(:tmp_dir) { Dir.mktmpdir }
      let(:origin_path) { File.join(tmp_dir, 'srv', 'group', 'project.git') }
      let(:reference_repository_path) { File.join(tmp_dir, 'ref.git') }
      let(:project_dir) { File.join(tmp_dir, 'build') }
      let(:workload_ref) { 'refs/workloads/abc123' }
      let(:env) do
        {
          'CI_PROJECT_DIR' => project_dir,
          'CI_WORKLOAD_REF' => workload_ref,
          'DUO_WORKFLOW_GIT_HTTP_BASE_URL' => "file://#{tmp_dir}/srv/",
          'GITLAB_PROJECT_PATH' => 'group/project',
          'DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH' => reference_repository_path,
          'GIT_CONFIG_NOSYSTEM' => '1',
          'GIT_CONFIG_COUNT' => '1',
          'GIT_CONFIG_KEY_0' => 'protocol.file.allow',
          'GIT_CONFIG_VALUE_0' => 'always'
        }
      end

      let!(:old_commit) { commits(3) }
      let!(:head_commit) { commits(2) }

      before do
        git('clone', '--quiet', '--bare', work_path, origin_path)
        git('-C', origin_path, 'update-ref', workload_ref, head_commit)
        git('init', '--quiet', '--bare', reference_repository_path)
        git('-C', reference_repository_path, 'fetch', '--quiet', origin_path, "#{old_commit}:refs/heads/main")
        # The runner restores the CI cache before the script runs.
        FileUtils.mkdir_p(File.join(project_dir, 'node_modules'))
        File.write(File.join(project_dir, 'node_modules', 'cached.js'), 'cached')
      end

      after do
        FileUtils.rm_rf(tmp_dir)
      end

      def work_path
        File.join(tmp_dir, 'work')
      end

      def git(*args, chdir: tmp_dir)
        output, status = Open3.capture2e(env, 'git', *args, chdir: chdir)
        raise "git #{args.join(' ')} failed: #{output}" unless status.success?

        output.strip
      end

      def commits(count)
        FileUtils.mkdir_p(work_path)
        git('init', '--quiet', work_path) unless File.directory?(File.join(work_path, '.git'))
        count.times do |i|
          File.write(File.join(work_path, "file_#{SecureRandom.hex(4)}"), i.to_s)
          git('-C', work_path, 'add', '.')
          git('-C', work_path, '-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '--quiet', '-m', 'c')
        end
        git('-C', work_path, 'rev-parse', 'HEAD')
      end

      # The prelude can override commands such as `sleep` with shell functions.
      def run_clone_commands(*prelude)
        Open3.capture2e(env, 'bash', '-eo', 'pipefail', '-c', [*prelude, *git_strategy.clone_commands].join("\n"))
      end

      def checkout_head
        git('-C', project_dir, 'rev-parse', 'HEAD')
      end

      def alternates
        path = File.join(project_dir, '.git', 'objects', 'info', 'alternates')
        File.exist?(path) ? File.read(path).strip : nil
      end

      it 'borrows objects from the reference repository and keeps the restored cache' do
        output, status = run_clone_commands

        expect(status).to be_success, output
        expect(checkout_head).to eq(head_commit)
        expect(alternates).to eq("#{reference_repository_path}/objects")
        expect(File.read(File.join(project_dir, 'node_modules', 'cached.js'))).to eq('cached')
        expect(git('-C', project_dir, 'fsck', '--connectivity-only')).not_to include('missing')
      end

      context 'when the reference repository does not exist' do
        before do
          env['DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH'] = File.join(tmp_dir, 'missing.git')
        end

        it 'clones the workload ref with git clone --revision' do
          output, status = run_clone_commands

          expect(status).to be_success, output
          expect(output).to include('Reference repository not found')
          expect(checkout_head).to eq(head_commit)
          expect(alternates).to be_nil
          # `git clone --revision` writes no fetch refspec; the init and fetch fallback does.
          expect(Open3.capture2e(env, 'git', '-C', project_dir, 'config', 'remote.origin.fetch').first).to be_empty
          expect(File.read(File.join(project_dir, 'node_modules', 'cached.js'))).to eq('cached')
        end

        context 'when the clone fails' do
          let(:unavailable_origin_path) { "#{origin_path}.unavailable" }

          before do
            FileUtils.mv(origin_path, unavailable_origin_path)
          end

          it 'discards the partial clone and retries' do
            # Between attempts, leave a partial clone behind and restore the origin.
            output, status = run_clone_commands(
              'sleep() { echo retrying; mkdir -p .duo-clone/partial; ' \
                "mv '#{unavailable_origin_path}' '#{origin_path}'; }"
            )

            expect(status).to be_success, output
            expect(output.scan('retrying').size).to eq(1)
            expect(checkout_head).to eq(head_commit)
            expect(File.exist?(File.join(project_dir, '.duo-clone'))).to be(false)
          end

          it 'exits after the last attempt fails' do
            output, status = run_clone_commands('sleep() { echo retrying; }')

            expect(status.exitstatus).to eq(1), output
            expect(output.scan('retrying').size).to eq(2)
            expect(File.exist?(File.join(project_dir, '.git'))).to be(false)
          end
        end
      end

      context 'when the workspace already has a repository' do
        before do
          git('clone', '--quiet', origin_path, File.join(tmp_dir, 'resumed'))
          FileUtils.mv(File.join(tmp_dir, 'resumed', '.git'), File.join(project_dir, '.git'))
          git('-C', project_dir, 'checkout', '--quiet', old_commit)
        end

        it 'keeps the resumed session untouched' do
          output, status = run_clone_commands

          expect(status).to be_success, output
          expect(output).to include('Keeping the existing repository')
          expect(checkout_head).to eq(old_commit)
        end
      end
    end
  end

  context 'without a reference repository path' do
    let(:reference_repository_path) { nil }

    it_behaves_like 'the runner clone'
  end

  context 'when dap_reference_repository is disabled' do
    before do
      stub_feature_flags(dap_reference_repository: false)
    end

    it_behaves_like 'the runner clone'
  end

  context 'when dap_git_credential_helper is disabled' do
    before do
      stub_feature_flags(dap_git_credential_helper: false)
    end

    it_behaves_like 'the runner clone'
  end
end
