# frozen_string_literal: true

module QA
  module EE
    module Scenario
      module Test
        module Integration
          # Selects the Duo Agent Platform flow smoke specs into their own e2e jobs, separate
          # from ai-gateway. On omnibus (duo-agent-platform), the gem-side
          # Test::Integration::DuoAgentPlatform scenario boots the agentic-mock Duo Workflow
          # Service alongside the mock AI Gateway. On CNG (cng-duo-agent-platform),
          # qa/caproni/caproni.duo-agent-platform.yaml deploys them.
          class DuoAgentPlatform < QA::Scenario::Test::Instance::All
            tags :duo_agent_platform

            pipeline_mappings test_on_omnibus: %w[duo-agent-platform], test_on_cng: %w[cng-duo-agent-platform]
          end
        end
      end
    end
  end
end
