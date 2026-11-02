# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120007_add_organization_fields_to_groups.rb')

RSpec.describe AddOrganizationFieldsToGroups, :elastic, feature_category: :global_search do
  let(:version) { 20261015120007 }

  include_examples 'migration adds mapping'
end
