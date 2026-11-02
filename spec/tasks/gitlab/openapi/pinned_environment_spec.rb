# frozen_string_literal: true

require 'fast_spec_helper'
require 'rake'
require_relative '../../../../lib/tasks/gitlab/openapi/pinned_environment'

RSpec.describe Tasks::Gitlab::Openapi::PinnedEnvironment, feature_category: :api do
  let(:config_path) { described_class::CONFIG_PATH }
  let(:environment_task) { instance_double(Rake::Task, invoke: nil) }
  let(:argv) { %w[--trace gitlab:openapi:v3:generate_and_validate] }

  before do
    allow(Rake::Task).to receive(:[]).with(:environment).and_return(environment_task)
    stub_const('ARGV', argv)
    allow(Rake.application).to receive(:original_dir).and_return('/checkout')
    allow(described_class).to receive(:exec)
    stub_env('OPENAPI_SIMULATE_SAAS', nil)
    stub_env('OPENAPI_PINNED_RERUN', nil)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))
  end

  describe '.boot!' do
    context 'when not in the development or test environment' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
      end

      it 'raises before re-running or booting' do
        expect(described_class).not_to receive(:exec)
        expect(environment_task).not_to receive(:invoke)

        expect { described_class.boot! }
          .to raise_error(RuntimeError, 'This task can only be run in the development or test environment')
      end
    end

    context 'when the environment is not pinned' do
      before do
        stub_env('GITLAB_CONFIG', nil)
        stub_env('GITLAB_SIMULATE_SAAS', 'true')
      end

      it 're-runs the whole rake command, flags included, with the pinned config and SaaS setting' do
        expect(described_class).to receive(:exec).with(
          { 'GITLAB_CONFIG' => config_path, 'GITLAB_SIMULATE_SAAS' => 'false', 'OPENAPI_PINNED_RERUN' => '1' },
          Gem.ruby, File.expand_path($PROGRAM_NAME, '/checkout'), *argv
        )

        described_class.boot!
      end

      context 'when it has already re-run' do
        before do
          stub_env('OPENAPI_PINNED_RERUN', '1')
        end

        it 'aborts instead of re-running again' do
          expect(described_class).not_to receive(:exec)

          expect { described_class.boot! }
            .to raise_error(SystemExit).and output(/still not pinned/).to_stderr
        end
      end

      context 'when OPENAPI_SIMULATE_SAAS is set' do
        before do
          stub_env('OPENAPI_SIMULATE_SAAS', 'true')
        end

        it 'pins GITLAB_SIMULATE_SAAS to its value' do
          expect(described_class).to receive(:exec)
            .with(hash_including('GITLAB_SIMULATE_SAAS' => 'true'), any_args)

          described_class.boot!
        end
      end
    end

    context 'when the environment is pinned' do
      before do
        stub_env('GITLAB_CONFIG', config_path)
        stub_env('GITLAB_SIMULATE_SAAS', 'false')
      end

      it 'boots Rails without re-running' do
        expect(described_class).not_to receive(:exec)
        expect(environment_task).to receive(:invoke)

        described_class.boot!
      end
    end
  end

  describe 'CONFIG_PATH' do
    it 'points to a config that enables the registry and dependency proxy' do
      config = ActiveSupport::ConfigurationFile.parse(config_path)

      expect(config.dig('development', 'registry', 'enabled')).to be(true)
      expect(config.dig('development', 'dependency_proxy', 'enabled')).to be(true)
    end
  end
end
