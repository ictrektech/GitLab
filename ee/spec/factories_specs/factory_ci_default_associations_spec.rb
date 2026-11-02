# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Factory default associations for CI records', feature_category: :tooling do
  it_behaves_like 'factory default associations', [
    FactoryDefaults::Row.new(
      factory: :security_scan, skip: :project, passed: { project: :project }, strategies: %i[create]
    )
  ]
end
