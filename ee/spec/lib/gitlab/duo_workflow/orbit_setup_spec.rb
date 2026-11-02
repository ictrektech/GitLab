# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::OrbitSetup, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }

  let(:checkout) { true }
  let(:remote_orbit) { true }

  let(:local_orbit_command) do
    <<~SH.strip
      if glab orbit --yes setup duo --yes --skip instructions --no-index; then
        glab orbit --yes workspace index --async . || glab orbit --yes index . || echo "Warning: Orbit local indexing failed; continuing without local index" >&2
      else
        echo "Warning: Orbit setup failed; continuing without the orbit skill and local index" >&2
      fi
    SH
  end

  let(:remote_skill_command) do
    'glab skills install --global --force orbit || echo "Warning: Orbit skill install failed; ' \
      'continuing without the orbit skill"'
  end

  subject(:commands) { described_class.new(current_user: user, checkout: checkout).commands }

  before do
    allow(::Ai::Orbit::Settings).to receive(:foundational_enabled?).with(user).and_return(remote_orbit)
  end

  describe '#commands' do
    context 'with a checkout' do
      context 'when remote Orbit is available to the agent' do
        it 'installs the orbit-cli skill with the workload credential, then indexes the checkout' do
          expect(commands).to eq([local_orbit_command])
        end
      end

      context 'when remote Orbit is not available to the agent' do
        let(:remote_orbit) { false }

        it 'installs the orbit-cli skill without a credential so it holds only local instructions' do
          expect(commands).to eq([local_orbit_command.sub('if glab', 'if GITLAB_TOKEN= glab')])
        end
      end

      context 'when duo_developer_orbit is disabled' do
        before do
          stub_feature_flags(duo_developer_orbit: false)
        end

        it 'falls back to the remote Orbit skill' do
          expect(commands).to eq([remote_skill_command])
        end

        context 'when remote Orbit is not available to the agent' do
          let(:remote_orbit) { false }

          it 'returns no commands' do
            expect(commands).to be_empty
          end
        end
      end
    end

    context 'without a checkout' do
      let(:checkout) { false }

      it 'installs the remote Orbit skill' do
        expect(commands).to eq([remote_skill_command])
      end

      context 'when remote Orbit is not available to the agent' do
        let(:remote_orbit) { false }

        it 'returns no commands' do
          expect(commands).to be_empty
        end
      end
    end

    describe 'running the local Orbit command' do
      # Runs the command against a stub glab that logs its arguments.
      def run_with_stub_glab(setup_exit_code: 0, async_exit_code: 0, index_exit_code: 0)
        Dir.mktmpdir do |dir|
          log = File.join(dir, 'calls.log')
          File.write(File.join(dir, 'glab'), <<~SH)
            #!/bin/sh
            echo "$*" >> #{log}
            case "$*" in
              *setup*) exit #{setup_exit_code} ;;
              *--async*) exit #{async_exit_code} ;;
              *index*) exit #{index_exit_code} ;;
            esac
          SH
          File.chmod(0o755, File.join(dir, 'glab'))

          _, stderr, = Open3.capture3({ 'PATH' => "#{dir}:#{ENV['PATH']}" }, 'sh', '-c', commands.first)

          [File.readlines(log, chomp: true), stderr]
        end
      end

      it 'indexes in the background after a successful setup' do
        calls, = run_with_stub_glab

        expect(calls).to eq(
          ['orbit --yes setup duo --yes --skip instructions --no-index', 'orbit --yes workspace index --async .']
        )
      end

      it 'falls back to the blocking index when orbit-cli rejects --async', :aggregate_failures do
        calls, stderr = run_with_stub_glab(async_exit_code: 2)

        expect(calls.last(2)).to eq(['orbit --yes workspace index --async .', 'orbit --yes index .'])
        expect(stderr).to be_empty
      end

      it 'warns and continues when both index attempts fail' do
        _, stderr = run_with_stub_glab(async_exit_code: 2, index_exit_code: 1)

        expect(stderr).to include('Warning: Orbit local indexing failed')
      end

      it 'skips the index when setup fails, so a failed download is not retried', :aggregate_failures do
        calls, stderr = run_with_stub_glab(setup_exit_code: 1)

        expect(calls).to eq(['orbit --yes setup duo --yes --skip instructions --no-index'])
        expect(stderr).to include('Warning: Orbit setup failed')
      end
    end
  end
end
