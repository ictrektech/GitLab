# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Auth::Vos::Client, feature_category: :system_access do
  let(:endpoint) { 'https://vos.example.com/v1000/oauth2' }
  let(:client) { described_class.new(endpoint: endpoint, client_id: 'com.ictrek.gitlab') }
  let(:introspection) do
    { active: true, aud: 'com.ictrek.gitlab', client_id: 'com.ictrek.gitlab',
      token_type: 'Bearer', scope: 'openid profile email', sub: 'subject-a', exp: 1.hour.from_now.to_i }
  end

  let(:claims) { { sub: 'subject-a', preferred_username: 'example', enable: 1, email: 'unverified@example.com' } }

  before do
    stub_request(:post, "#{endpoint}/introspect").to_return(status: 200, body: introspection.to_json)
    stub_request(:get, "#{endpoint}/userinfo").with(headers: { Authorization: 'Bearer test-token' })
      .to_return(status: 200, body: claims.to_json)
  end

  it 'derives identity and placeholder email from the stable subject' do
    result = client.verify('test-token')
    claims[:preferred_username] = 'renamed'
    stub_request(:get, "#{endpoint}/userinfo").to_return(status: 200, body: claims.to_json)
    expect(client.verify('test-token').slice(:uid, :email)).to eq(result.slice(:uid, :email))
    expect(result[:email]).to end_with('@users.invalid')
  end

  [[:active, false], [:aud, 'another-app'], [:client_id, 'another-app'],
    [:scope, 'profile'], [:exp, 0], [:token_type, 'refresh_token']].each do |key, value|
    it "rejects invalid introspection #{key}" do
      introspection[key] = value
      stub_request(:post, "#{endpoint}/introspect").to_return(status: 200, body: introspection.to_json)
      expect { client.verify('test-token') }.to raise_error(described_class::InvalidIdentity)
    end
  end

  it 'rejects disabled users and subject mismatches' do
    [claims.merge(enable: 0), claims.merge(sub: 'subject-b')].each do |invalid|
      stub_request(:get, "#{endpoint}/userinfo").to_return(status: 200, body: invalid.to_json)
      expect { client.verify('test-token') }.to raise_error(described_class::InvalidIdentity)
    end
  end

  it 'fails closed when VOS is unavailable' do
    stub_request(:post, "#{endpoint}/introspect").to_timeout
    expect { client.verify('test-token') }.to raise_error(described_class::InvalidIdentity)
  end
end
