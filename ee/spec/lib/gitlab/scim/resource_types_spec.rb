# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::ResourceTypes, feature_category: :system_access do
  describe '.all' do
    it 'returns only the User resource type for group SCIM' do
      expect(described_class.all(context: :group).pluck(:id)).to eq(%w[User])
    end

    it 'returns the User and Group resource types for instance SCIM' do
      expect(described_class.all(context: :instance).pluck(:id)).to eq(%w[User Group])
    end
  end

  describe '.find' do
    it 'returns the resource type with its schema' do
      expect(described_class.find('User', context: :group)).to eq(
        schemas: ['urn:ietf:params:scim:schemas:core:2.0:ResourceType'],
        id: 'User',
        name: 'User',
        endpoint: '/Users',
        description: 'User Account',
        schema: Gitlab::Scim::SchemaDefinitions::User::SCHEMA_ID
      )
    end

    it 'returns nil for a resource type that is not available in the context' do
      expect(described_class.find('Group', context: :group)).to be_nil
    end
  end
end
