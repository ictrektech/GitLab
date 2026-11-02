# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Projects::SaveProjectService, feature_category: :groups_and_projects do
  describe '#input_schema' do
    subject(:schema) { described_class.new(tools: []).input_schema }

    it 'includes the EE custom template parameters' do
      properties = schema[:properties]

      expect(properties).to include(
        use_custom_template: hash_including(type: 'boolean'),
        group_with_project_templates_id: hash_including(type: 'integer'),
        template_project_id: hash_including(type: 'integer')
      )
    end

    it 'inherits the CE template_name parameter' do
      expect(schema[:properties]).to include(template_name: hash_including(type: 'string'))
    end
  end

  describe '.create_project_mcp_params' do
    it 'includes the CE and EE template parameters' do
      expect(described_class::CREATE_PARAMS).to include(
        :template_name,
        :template_project_id,
        :use_custom_template,
        :group_with_project_templates_id
      )
    end
  end
end
