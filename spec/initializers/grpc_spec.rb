# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'config/initializers/grpc', feature_category: :gitaly do
  subject(:load_initializer) { load Rails.root.join('config/initializers/grpc.rb') }

  before do
    allow(GRPC::Core::ChannelCredentials).to receive(:set_default_roots_pem)
  end

  it "points gRPC's default roots at the GitLab CA bundle" do
    bundle = "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n"
    allow(Gitlab::X509::Certificate).to receive(:ca_certs_bundle).and_return(bundle)

    load_initializer

    expect(GRPC::Core::ChannelCredentials).to have_received(:set_default_roots_pem).with(bundle)
  end

  it 'does not override the default roots when the CA bundle is blank' do
    allow(Gitlab::X509::Certificate).to receive(:ca_certs_bundle).and_return('')

    load_initializer

    expect(GRPC::Core::ChannelCredentials).not_to have_received(:set_default_roots_pem)
  end
end
