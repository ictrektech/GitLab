# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::GroupScimAuthAccessTokenEntity, feature_category: :system_access do
  let(:group) { build_stubbed(:group, path: 'my-group') }

  let(:scim_token) do
    build_stubbed(:group_scim_auth_access_token, group: group).tap do |token|
      token.set_token('glsoat-testtoken')
    end
  end

  subject(:json) { described_class.new(scim_token).as_json }

  it 'exposes the group SCIM URL' do
    expect(json[:scim_api_url]).to end_with('/api/scim/v2/groups/my-group')
  end

  it 'exposes the token' do
    expect(json[:scim_token]).to eq('glsoat-testtoken')
  end
end
