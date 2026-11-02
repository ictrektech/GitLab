# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP tool annotation declarations', feature_category: :ai_agents do
  describe 'every registered tool declares a readOnlyHint annotation' do
    let(:manager) { Mcp::Tools::Manager.new }

    it 'has no tools missing readOnlyHint' do
      offenders = manager.tools.reject { |_name, tool| tool.annotations.key?(:readOnlyHint) }.keys

      expect(offenders).to be_empty,
        "Tools missing a readOnlyHint annotation: #{offenders}. Add `readOnlyHint` to register_version " \
          "annotations (service classes) or route_setting :mcp annotations (API routes)."
    end
  end
end
