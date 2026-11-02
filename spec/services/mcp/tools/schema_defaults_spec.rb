# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP tool schemas', feature_category: :mcp_server do
  def schema_fields(node, path = 'input_schema')
    case node
    when Hash
      node.flat_map { |key, value| [["#{path}.#{key}", key.to_s, value], *schema_fields(value, "#{path}.#{key}")] }
    when Array
      node.each_with_index.flat_map { |value, index| schema_fields(value, "#{path}[#{index}]") }
    else
      []
    end
  end

  Mcp::Tools::Manager.new.tools.each do |name, tool|
    it "#{name} states no defaults" do
      fields = [['description', 'description', tool.description.to_s], *schema_fields(tool.input_schema)]

      violations = fields.filter_map do |field, key, value|
        stated = key == 'default' ||
          (key == 'description' && value.is_a?(String) &&
            value.gsub(/\bdefault branch(es)?\b/i, '').match?(/\bdefault/i))

        "#{field}: #{value.inspect}" if stated
      end

      expect(violations).to be_empty, "#{name} states a default, which is not allowed:\n#{violations.join("\n")}"
    end
  end
end
