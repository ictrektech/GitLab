# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::SchemaDefinitions::User, feature_category: :system_access do
  subject(:schema) { described_class.to_h(context: :group) }

  it 'describes the core User schema' do
    expect(schema).to include(id: 'urn:ietf:params:scim:schemas:core:2.0:User', name: 'User')
  end

  it 'does not override Class#name' do
    expect(described_class.name).to eq('Gitlab::Scim::SchemaDefinitions::User')
  end

  it 'only advertises the attributes GitLab processes' do
    expect(schema[:attributes].pluck(:name)).to eq(%w[id externalId userName name displayName emails active])
  end

  context 'with the instance context' do
    subject(:schema) { described_class.to_h(context: :instance) }

    it 'also advertises the read-only groups attribute' do
      groups = schema[:attributes].find { |attr| attr[:name] == 'groups' }

      expect(groups).to include(type: 'complex', multiValued: true, mutability: 'readOnly')
      expect(groups[:subAttributes].pluck(:name)).to eq(%w[value display type])
    end

    it 'marks the group identifier as case insensitive' do
      groups = schema[:attributes].find { |attr| attr[:name] == 'groups' }

      expect(groups[:subAttributes].find { |attr| attr[:name] == 'value' }).to include(caseExact: false)
    end
  end

  it 'marks the identifiers as case insensitive because extern_uid lookups ignore case' do
    attributes = schema[:attributes].index_by { |attr| attr[:name] }

    expect(attributes.values_at('id', 'externalId').pluck(:caseExact)).to all(be(false))
  end

  it 'marks userName as required, unique and immutable' do
    user_name = schema[:attributes].find { |attr| attr[:name] == 'userName' }

    expect(user_name).to include(type: 'string', required: true, uniqueness: 'server', mutability: 'immutable')
  end

  it 'marks the attributes GitLab does not update after provisioning as immutable' do
    attributes = schema[:attributes].index_by { |attr| attr[:name] }

    expect(attributes.values_at('userName', 'name', 'displayName', 'emails').pluck(:mutability)).to all(eq('immutable'))
    expect(attributes['name'][:subAttributes].pluck(:mutability)).to all(eq('immutable'))
    expect(attributes['emails'][:subAttributes].pluck(:mutability)).to all(eq('immutable'))
  end

  it 'marks the attributes required for provisioning as required' do
    required = schema[:attributes].select { |attr| attr[:required] }.pluck(:name)

    expect(required).to contain_exactly('externalId', 'userName', 'emails')
  end

  it 'does not advertise attributes that GitLab never returns as returned' do
    attributes = schema[:attributes].index_by { |attr| attr[:name] }

    expect(attributes['externalId']).to include(mutability: 'writeOnly', returned: 'never')
    expect(attributes['displayName']).to include(returned: 'never')
  end

  it 'describes the supported name and emails sub-attributes' do
    attributes = schema[:attributes].index_by { |attr| attr[:name] }

    expect(attributes['name'][:subAttributes].pluck(:name)).to eq(%w[formatted givenName familyName])
    expect(attributes['emails'][:subAttributes].pluck(:name)).to eq(%w[value type primary])
    expect(attributes['emails']).to include(multiValued: true)
  end

  it 'only includes the RFC 7643 attribute characteristics' do
    allowed_keys = %i[name type multiValued description required caseExact mutability returned uniqueness
      subAttributes referenceTypes]

    expect(schema[:attributes].flat_map(&:keys).uniq - allowed_keys).to be_empty
  end
end
