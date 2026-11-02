# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::SchemaDefinitions, feature_category: :system_access do
  let(:user_schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:User' }
  let(:group_schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:Group' }

  describe '.all' do
    it 'returns only the User schema for group SCIM' do
      expect(described_class.all(context: :group).pluck(:id)).to eq([user_schema_id])
    end

    it 'returns the User and Group schemas for instance SCIM' do
      expect(described_class.all(context: :instance).pluck(:id)).to match_array([user_schema_id, group_schema_id])
    end

    it 'raises for an unknown context' do
      expect { described_class.all(context: :unknown) }.to raise_error(KeyError)
    end
  end

  describe '.find' do
    it 'returns the schema by URN' do
      expect(described_class.find(user_schema_id, context: :group)).to include(id: user_schema_id, name: 'User')
    end

    it 'returns nil for a schema that is not available in the context' do
      expect(described_class.find(group_schema_id, context: :group)).to be_nil
    end

    it 'only includes the groups attribute on the User schema for instance SCIM' do
      group_user = described_class.find(user_schema_id, context: :group)
      instance_user = described_class.find(user_schema_id, context: :instance)

      expect(group_user[:attributes].pluck(:name)).not_to include('groups')
      expect(instance_user[:attributes].pluck(:name)).to include('groups')
    end

    it 'returns nil for an unknown schema' do
      expect(described_class.find('urn:unknown', context: :instance)).to be_nil
    end
  end
end
