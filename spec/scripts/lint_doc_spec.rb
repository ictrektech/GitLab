# frozen_string_literal: true

require 'fast_spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'scripts/lint-doc.sh', feature_category: :tooling do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:bin_dir) { File.join(tmp_dir, 'bin') }
  let(:vale_log) { File.join(tmp_dir, 'vale.log') }

  let(:vale_command) { %w[vale --minAlertLevel error --output=doc/.vale/vale.tmpl doc/first.md doc/second.md] }

  # Stand-ins that record each argument they get on its own line and exit with VALE_EXIT_STATUS.
  # The container runtimes also answer the `info` probe the script sends first.
  let(:fake_vale) { %(printf '%s\\n' vale "$@" > "$VALE_LOG"\nexit "$VALE_EXIT_STATUS") }
  let(:fake_runtime) { %([ "$1" = info ] && exit 0\nprintf '%s\\n' "$@" > "$VALE_LOG"\nexit "$VALE_EXIT_STATUS") }

  before do
    # The script lints the directory above its own, so it gets a checkout of its own.
    FileUtils.mkdir_p(%w[scripts doc bin].map { |dir| File.join(tmp_dir, dir) })
    FileUtils.cp(File.expand_path('../../scripts/lint-doc.sh', __dir__), File.join(tmp_dir, 'scripts'))
    File.write(File.join(tmp_dir, 'CHANGELOG.md'), "## 1.0.0\n")
    %w[first second].each { |name| File.write(File.join(tmp_dir, 'doc', "#{name}.md"), "# Page\n") }

    # PATH holds only these tools, so Vale and the container runtimes are found only where a test adds them.
    %w[bash dirname find grep sed sort uniq whoami].each do |tool|
      File.symlink(executable(tool), File.join(bin_dir, tool))
    end
    write_tool('markdownlint-cli2', 'exit 0')
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def executable(tool)
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find do |path|
      File.executable?(path)
    end
  end

  def write_tool(name, body)
    path = File.join(bin_dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_script(vale_exit_status: 0, files: %w[doc/first.md doc/second.md])
    env = { 'PATH' => bin_dir, 'VALE_LOG' => vale_log, 'VALE_EXIT_STATUS' => vale_exit_status.to_s }

    Open3.capture2e(env, File.join(tmp_dir, 'scripts', 'lint-doc.sh'), *files, unsetenv_others: true)
  end

  def recorded_arguments
    File.readlines(vale_log, chomp: true)
  end

  shared_examples 'runs Vale on the files it is given' do
    it 'passes the files to Vale', :aggregate_failures do
      output, _status = run_script

      expect(output).not_to include('vale failed with errors!')
      expect(recorded_arguments.last(vale_command.size)).to eq(vale_command)
    end

    it 'fails when Vale reports errors', :aggregate_failures do
      output, status = run_script(vale_exit_status: 1)

      expect(status.exitstatus).to eq(1)
      expect(output).to include('vale failed with errors!')
    end
  end

  context 'when Vale is installed' do
    before do
      write_tool('vale', fake_vale)
    end

    it_behaves_like 'runs Vale on the files it is given'
  end

  %w[nerdctl docker].each do |runtime|
    context "when Vale is not installed and #{runtime} is available" do
      before do
        write_tool(runtime, fake_runtime)
      end

      it_behaves_like 'runs Vale on the files it is given'

      it "runs Vale with #{runtime} in the documentation linting image", :aggregate_failures do
        run_script

        expect(recorded_arguments.first).to eq('run')
        expect(recorded_arguments).to include(
          a_string_starting_with('registry.gitlab.com/gitlab-org/technical-writing/docs-gitlab-com/lint-markdown:')
        )
      end

      it 'mounts the checkout at its own path, so an absolute path names the same file in the container',
        :aggregate_failures do
        absolute_path = File.join(tmp_dir, 'doc', 'first.md')

        run_script(files: [absolute_path])

        expect(recorded_arguments.each_cons(2).to_a).to include(['-v', "#{tmp_dir}:#{tmp_dir}"], ['-w', tmp_dir])
        expect(recorded_arguments.last).to eq(absolute_path)
      end
    end
  end
end
