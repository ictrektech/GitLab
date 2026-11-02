# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120008_add_organization_fields_to_users.rb')

RSpec.describe AddOrganizationFieldsToUsers, :elastic, feature_category: :global_search do
  let(:version) { 20261015120008 }

  include_examples 'migration adds mapping'
end
