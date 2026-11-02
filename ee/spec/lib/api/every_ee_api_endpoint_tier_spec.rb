# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Every EE API endpoint tier', feature_category: :api do
  let(:allowlist_path) { 'ee/spec/support/api/routes_without_tier.yml' }
  let(:allowlist) { YAML.safe_load_file(Rails.root.join(allowlist_path)) }

  # Matches the routes the OpenAPI v3 generator documents (see lib/tasks/gitlab/openapi/v3_document.rb).
  let(:documented_ee_routes) do
    excluded = Gitlab::GrapeOpenapi.configuration.excluded_api_classes
    ::API::API # rubocop:disable Lint/Void -- Referenced so every API class is mounted

    ::API::Base.descendants.reject { |klass| excluded.include?(klass.name) }.flat_map(&:routes).select do |route|
      route.request_method != '*' &&
        !route.options.dig(:settings, :description, :hidden) &&
        route.app.source.source_location.first.start_with?(Rails.root.join('ee/').to_s)
    end
  end

  let(:routes_without_tier) do
    documented_ee_routes.reject { |route| route.settings[:tier] }.map { |route| route_key(route) }.uniq
  end

  it 'declares a tier on every documented EE route, or allowlists it' do
    missing = routes_without_tier - allowlist

    expect(missing).to be_empty, <<~MESSAGE
      These EE API routes have no `route_setting :tier`:
      #{missing.sort.map { |key| "- #{key}" }.join("\n")}

      Add `route_setting :tier, :premium` or `route_setting :tier, :ultimate` above the route's
      `route_setting :authorization`, using the lowest tier at which the endpoint does something useful.
      If the route is available on every tier, add it to #{allowlist_path} with a reason.
    MESSAGE
  end

  it 'has no stale allowlist entries' do
    stale = allowlist - routes_without_tier

    expect(stale).to be_empty, <<~MESSAGE
      Remove these entries from #{allowlist_path}. The routes either declare a tier now or no longer exist:
      #{stale.sort.map { |key| "- #{key}" }.join("\n")}
    MESSAGE
  end

  def route_key(route)
    "#{route.request_method} #{route.path.delete_suffix('(.:format)').delete_prefix('/api/:version')}"
  end
end
