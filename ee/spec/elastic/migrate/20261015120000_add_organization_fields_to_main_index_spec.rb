# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120000_add_organization_fields_to_main_index.rb')

RSpec.describe AddOrganizationFieldsToMainIndex, :elastic, feature_category: :global_search do
  let(:version) { 20261015120000 }

  include_examples 'migration adds mapping'
end
