# frozen_string_literal: true

module WorkItems
  module Widgets
    class AiSession < Base
      def duo_workflows
        work_item.duo_workflows.without_foundational_chat_agents
      end
    end
  end
end
