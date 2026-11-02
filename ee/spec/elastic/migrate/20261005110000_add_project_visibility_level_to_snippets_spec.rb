# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261005110000_add_project_visibility_level_to_snippets.rb')

RSpec.describe AddProjectVisibilityLevelToSnippets, :elastic, feature_category: :global_search do
  let(:version) { 20261005110000 }

  include_examples 'migration adds mapping'
end
