# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Errors, feature_category: :importers do
  %i[
    ProviderIdentityError
    StaleApplicationError
    PlaceholderReferenceLoadError
    MappingConflictError
    ProviderObjectError
    MissingCredentialsError
  ].each do |name|
    it "defines #{name} as a StandardError subclass" do
      expect(described_class.const_get(name, false)).to be < StandardError
    end
  end
end
