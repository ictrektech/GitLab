# frozen_string_literal: true

# Builds the tool for every MCP-enabled Grape route instead of calling tools/list, so routes
# outside the default toolsets and routes folded into aggregated tools are checked too.
RSpec.shared_examples 'a Grape-backed MCP tool' do
  let(:json_schema_primitive_types) { %w[null boolean object array number string integer] }

  it 'declares a valid JSON Schema primitive type for every input property', :aggregate_failures do
    # Same route source as Mcp::Tools::Manager#mcp_routes; API::API's mounted copies hold non-Hash param values.
    routes = (::API::Base.descendants - [::API::API]).flat_map(&:routes)

    api_tools = routes.filter_map do |route|
      settings = route.app.route_setting(:mcp)
      next if settings.blank?

      Mcp::Tools::Base::ApiTool.new(name: settings[:tool_name].to_s, route: route)
    end

    expect(api_tools).not_to be_empty, 'No MCP-enabled API routes were discovered'

    api_tools.each do |tool|
      tool_name = tool.name

      begin
        properties = tool.input_schema.deep_stringify_keys['properties'] || {}
      rescue StandardError => e
        expect(e).to be_nil,
          "Tool '#{tool_name}' (#{tool.route.request_method} #{tool.route.path}) could not build its " \
            "input schema: #{e.class}: #{e.message}"
        next
      end

      properties.each do |param_name, param_schema|
        expect(param_schema['type']).to be_in(json_schema_primitive_types),
          "Tool '#{tool_name}' has parameter '#{param_name}' with invalid JSON Schema type " \
            "#{param_schema['type'].inspect}. Valid types: #{json_schema_primitive_types.join(', ')}. " \
            "Current schema: #{param_schema.inspect}"

        next unless param_schema['type'] == 'array'

        expect(param_schema).to have_key('items'),
          "Tool '#{tool_name}' has array parameter '#{param_name}' without 'items' property. " \
            "JSON Schema requires array types to specify what's in the array using the 'items' property. " \
            "Current schema: #{param_schema.inspect}"

        expect(param_schema.dig('items', 'type')).to be_in(json_schema_primitive_types),
          "Tool '#{tool_name}' has array parameter '#{param_name}' with invalid items type " \
            "#{param_schema.dig('items', 'type').inspect}. Current schema: #{param_schema.inspect}"
      end
    end
  end
end
