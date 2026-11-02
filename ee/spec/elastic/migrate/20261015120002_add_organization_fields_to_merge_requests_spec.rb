# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261015120002_add_organization_fields_to_merge_requests.rb')

RSpec.describe AddOrganizationFieldsToMergeRequests, :elastic, feature_category: :global_search do
  let(:version) { 20261015120002 }

  include_examples 'migration adds mapping'
end
