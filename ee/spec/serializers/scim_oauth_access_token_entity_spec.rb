# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ScimOauthAccessTokenEntity, feature_category: :user_management do
  let(:scim_token) do
    build_stubbed(:scim_oauth_access_token).tap { |token| token.set_token('glsoat-testtoken') }
  end

  subject(:json) { described_class.new(scim_token).as_json }

  it 'exposes the instance SCIM URL' do
    expect(json[:scim_api_url]).to end_with('/api/scim/v2/application')
  end

  it 'exposes the token' do
    expect(json[:scim_token]).to eq('glsoat-testtoken')
  end
end
