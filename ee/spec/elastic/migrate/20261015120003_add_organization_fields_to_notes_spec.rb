# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120003_add_organization_fields_to_notes.rb')

RSpec.describe AddOrganizationFieldsToNotes, :elastic, feature_category: :global_search do
  let(:version) { 20261015120003 }

  include_examples 'migration adds mapping'
end
