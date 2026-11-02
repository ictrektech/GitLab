# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Scim::ServiceProviderConfig, feature_category: :system_access do
  subject(:config) { described_class.to_h(context: :group) }

  it 'uses the ServiceProviderConfig schema' do
    expect(config[:schemas]).to eq(['urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig'])
  end

  it 'advertises only the supported SCIM features' do
    expect(config).to include(
      patch: { supported: true },
      bulk: { supported: false, maxOperations: 0, maxPayloadSize: 0 },
      changePassword: { supported: false },
      sort: { supported: false },
      etag: { supported: false }
    )
  end

  it 'limits filter results to the maximum page size' do
    expect(config[:filter]).to eq(supported: true, maxResults: Kaminari.config.max_per_page)
  end

  it 'advertises bearer token authentication' do
    expect(config[:authenticationSchemes]).to contain_exactly(include(type: 'oauthbearertoken', primary: true))
  end

  it 'links to the group SCIM setup documentation' do
    expect(config[:documentationUri]).to end_with('/help/user/group/saml_sso/scim_setup.md')
  end

  it 'links to the instance SCIM setup documentation for instance SCIM' do
    expect(described_class.to_h(context: :instance)[:documentationUri])
      .to end_with('/help/administration/settings/scim_setup.md')
  end

  it 'raises for an unknown context' do
    expect { described_class.to_h(context: :unknown) }.to raise_error(ArgumentError)
  end
end
