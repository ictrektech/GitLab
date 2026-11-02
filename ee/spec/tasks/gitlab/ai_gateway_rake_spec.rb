# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:ai_gateway rake tasks', feature_category: :duo_agent_platform do
  before do
    Rake.application.rake_require 'tasks/gitlab/ai_gateway'
    Rake::Task.define_task(:gitlab_environment)
  end

  describe 'gitlab:ai_gateway:install' do
    let(:task) { Rake::Task['gitlab:ai_gateway:install'] }
    let(:path) { '/tmp/tests/gitlab-ai-gateway' }

    before do
      task.reenable

      # Stubbed one level below the task's own entry point, so a task naming a
      # method the module does not have raises NoMethodError here rather than
      # passing against an unverified partial double.
      allow(::Tasks::Gitlab::AiGateway::Utils).to receive(:install_with_retry).and_call_original
      allow(::Tasks::Gitlab::AiGateway::Utils).to receive(:install)
    end

    context 'when path argument is provided' do
      it 'installs at the provided path, with retries' do
        task.invoke(path)

        expect(::Tasks::Gitlab::AiGateway::Utils).to have_received(:install_with_retry).with(path: path)
        expect(::Tasks::Gitlab::AiGateway::Utils).to have_received(:install).with(path: path)
      end
    end

    context 'when path argument is not provided' do
      it 'installs at the default path, with retries' do
        task.invoke

        # No path argument means no keyword, so the method's own default supplies it.
        expect(::Tasks::Gitlab::AiGateway::Utils).to have_received(:install_with_retry).with(no_args)
        expect(::Tasks::Gitlab::AiGateway::Utils).to have_received(:install)
          .with(path: ::Tasks::Gitlab::AiGateway::Utils::DEFAULT_INSTALLATION_DIR)
      end
    end
  end
end
