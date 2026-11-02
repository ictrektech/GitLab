# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::SchemaDefinitions::Group, feature_category: :system_access do
  subject(:schema) { described_class.to_h(context: :instance) }

  it 'describes the core Group schema' do
    expect(schema).to include(id: 'urn:ietf:params:scim:schemas:core:2.0:Group', name: 'Group')
  end

  it 'only advertises the attributes GitLab processes' do
    expect(schema[:attributes].pluck(:name)).to eq(%w[id displayName members])
  end

  it 'marks displayName as required and immutable' do
    display_name = schema[:attributes].find { |attr| attr[:name] == 'displayName' }

    expect(display_name).to include(required: true, mutability: 'immutable')
  end

  it 'describes the members sub-attributes' do
    members = schema[:attributes].find { |attr| attr[:name] == 'members' }

    expect(members).to include(type: 'complex', multiValued: true)
    expect(members[:subAttributes].pluck(:name)).to eq(%w[value display type])
  end

  it 'marks the identifiers as case insensitive' do
    attributes = schema[:attributes].index_by { |attr| attr[:name] }
    member_value = attributes['members'][:subAttributes].find { |attr| attr[:name] == 'value' }

    expect([attributes['id'], member_value].pluck(:caseExact)).to all(be(false))
  end
end
