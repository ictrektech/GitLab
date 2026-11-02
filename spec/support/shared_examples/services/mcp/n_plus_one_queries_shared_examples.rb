# frozen_string_literal: true

# Requires `service` (credentials set), `arguments`, and a `create_additional_records` method.
RSpec.shared_examples 'an MCP tool that avoids N+1 queries' do |threshold: 0|
  include GraphqlHelpers

  it 'does not run queries per returned record', :aggregate_failures do
    raise 'Remove the :request_store tag from this spec' if ::Gitlab::SafeRequestStore.active?

    execute_tool = -> do
      ::Gitlab::SafeRequestStore.ensure_request_store do
        with_clean_rails_cache do
          with_clean_batchloader_executor { service.execute(params: { arguments: arguments }) }
        end
      end
    end

    execute_tool.call

    control_result = nil
    control = ActiveRecord::QueryRecorder.new(skip_cached: false) { control_result = execute_tool.call }
    expect(control_result[:isError]).to be(false)

    create_additional_records

    result = nil
    expect { result = execute_tool.call }.to match_query_count(control).with_threshold(threshold)
    expect(result[:isError]).to be(false)
    expect(result).not_to eq(control_result)
  end
end
