# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:context, :duo_workflow_service) do
    ::Tasks::Gitlab::AiGateway::Utils.ensure_duo_workflow_service
  rescue ::Tasks::Gitlab::AiGateway::Utils::InstallationError => e
    # A failed clone or `poetry install` means the environment could not be built,
    # which is not a defect in any spec. Failing here would pin it on whichever
    # tagged file happens to run first. `print_warn` has already logged the cause.
    skip("AI Gateway environment unavailable: #{e.message}")
  end

  config.after(:each, :duo_workflow_service) do |example|
    next unless example.exception

    tail = ::Tasks::Gitlab::AiGateway::Utils.duo_workflow_service_log_tail
    puts tail if tail
  end

  config.after(:suite) do
    ::Tasks::Gitlab::AiGateway::Utils.terminate_duo_workflow_service
  end
end
