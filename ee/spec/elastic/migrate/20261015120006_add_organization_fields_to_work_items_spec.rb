# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120006_add_organization_fields_to_work_items.rb')

RSpec.describe AddOrganizationFieldsToWorkItems, :elastic, feature_category: :global_search do
  let(:version) { 20261015120006 }

  include_examples 'migration adds mapping'
end
