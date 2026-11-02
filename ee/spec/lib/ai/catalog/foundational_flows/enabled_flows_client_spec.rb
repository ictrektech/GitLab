# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlows::EnabledFlowsClient, :use_clean_rails_memory_store_caching,
  feature_category: :duo_agent_platform do
  let(:endpoint_url) { 'https://cloud.gitlab.com/ai/v1/flows/enabled' }
  let(:auth_headers) { { 'Authorization' => 'Bearer instance-token' } }

  subject(:enabled_flows) { described_class.new.execute }

  before do
    stub_env('DEVELOPMENT_AI_GATEWAY_URL', nil)
    allow(Gitlab::AiGateway).to receive(:headers).and_return(auth_headers)
  end

  def stub_enabled_flows(status: 200, body: { enabled_flows: %w[bl_security] })
    stub_request(:get, endpoint_url)
      .with(headers: auth_headers)
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'returns the flows GitLab enabled for the instance' do
    stub_enabled_flows

    expect(enabled_flows).to eq(%w[bl_security])
  end

  it 'authenticates as the instance, without a user' do
    stub_enabled_flows

    enabled_flows

    expect(Gitlab::AiGateway).to have_received(:headers).with(user: nil, unit_primitive_name: :duo_agent_platform)
  end

  it 'uses a short timeout' do
    stub_enabled_flows
    expect(Gitlab::HTTP).to receive(:get).with(endpoint_url, hash_including(timeout: 2.seconds)).and_call_original

    enabled_flows
  end

  it 'never asks a self-hosted AI gateway' do
    stub_application_setting(ai_gateway_url: 'https://gateway.tenant.example.com')
    request = stub_enabled_flows
    tenant_request = stub_request(:get, %r{\Ahttps://gateway\.tenant\.example\.com})

    expect(enabled_flows).to eq(%w[bl_security])
    expect(request).to have_been_requested
    expect(tenant_request).not_to have_been_requested
  end

  it 'caches a success for 30 minutes' do
    request = stub_enabled_flows

    2.times { described_class.new.execute }
    expect(request).to have_been_requested.once

    travel_to(31.minutes.from_now) { described_class.new.execute }
    expect(request).to have_been_requested.twice
  end

  it 'memoizes the result for the request', :request_store do
    request = stub_enabled_flows
    allow(Rails.cache).to receive(:fetch).and_call_original

    2.times { described_class.new.execute }

    expect(request).to have_been_requested.once
    expect(Rails.cache).to have_received(:fetch).with(described_class::CACHE_KEY, any_args).once
  end

  it 'passes race_condition_ttl to the cache' do
    stub_enabled_flows

    expect(Rails.cache).to receive(:fetch)
      .with(described_class::CACHE_KEY, hash_including(race_condition_ttl: described_class::RACE_CONDITION_TTL))
      .and_call_original

    enabled_flows
  end

  shared_examples 'failing closed' do
    it 'returns no flows and caches that for 5 minutes' do
      expect(Gitlab::AppLogger).to receive(:error).twice

      2.times { expect(described_class.new.execute).to eq([]) }
      expect(request).to have_been_requested.once

      travel_to(6.minutes.from_now) { described_class.new.execute }
      expect(request).to have_been_requested.twice
    end
  end

  context 'when the AI gateway returns an error' do
    let!(:request) { stub_enabled_flows(status: 500, body: { detail: 'error' }) }

    it_behaves_like 'failing closed'
  end

  context 'when the request times out' do
    let!(:request) { stub_request(:get, endpoint_url).to_timeout }

    it_behaves_like 'failing closed'
  end

  it 'caches the answer for 30 minutes and the last good answer for a day' do
    stub_enabled_flows
    allow(Rails.cache).to receive(:write).and_call_original

    enabled_flows

    expect(Rails.cache).to have_received(:write)
      .with(described_class::CACHE_KEY, %w[bl_security], hash_including(expires_in: 30.minutes))
    expect(Rails.cache).to have_received(:write)
      .with(described_class::LAST_GOOD_CACHE_KEY, %w[bl_security], expires_in: 1.day)
  end

  context 'when a previous lookup succeeded' do
    before do
      stub_enabled_flows
      described_class.new.execute
    end

    def execute_later
      travel_to(31.minutes.from_now) { described_class.new.execute }
    end

    it 'uses the last good answer when the AI gateway returns an error, for 5 minutes' do
      stub_enabled_flows(status: 503, body: { detail: 'error' })
      allow(Rails.cache).to receive(:write).and_call_original

      expect(execute_later).to eq(%w[bl_security])
      expect(Rails.cache).to have_received(:write)
        .with(described_class::CACHE_KEY, %w[bl_security], hash_including(expires_in: 5.minutes))
    end

    it 'uses the last good answer when the request times out' do
      stub_request(:get, endpoint_url).to_timeout

      expect(execute_later).to eq(%w[bl_security])
    end

    it 'honours a successful empty answer and keeps it as the last good answer' do
      stub_enabled_flows(body: { enabled_flows: [] })
      expect(execute_later).to eq([])

      stub_request(:get, endpoint_url).to_timeout
      expect(travel_to(62.minutes.from_now) { described_class.new.execute }).to eq([])
    end

    it 'does not refresh the last good answer on a failure' do
      stub_enabled_flows(status: 503, body: { detail: 'error' })
      allow(Rails.cache).to receive(:write).and_call_original

      expect(travel_to(23.hours.from_now) { described_class.new.execute }).to eq(%w[bl_security])
      expect(Rails.cache).not_to have_received(:write).with(described_class::LAST_GOOD_CACHE_KEY, any_args)

      expect(travel_to(25.hours.from_now) { described_class.new.execute }).to eq([])
    end

    it 'stops using the last good answer after a day' do
      stub_enabled_flows(status: 503, body: { detail: 'error' })

      expect(travel_to(1.day.from_now + 1.minute) { described_class.new.execute }).to eq([])
    end
  end

  context 'when the response is not a list of flows' do
    let!(:request) { stub_enabled_flows(body: { enabled_flows: 'bl_security' }) }

    it_behaves_like 'failing closed'

    it 'returns no flows' do
      expect(enabled_flows).to eq([])
    end
  end

  context 'when the list mixes flow ids with other values' do
    before do
      stub_enabled_flows(body: { enabled_flows: ['bl_security', 1, nil] })
    end

    it 'keeps only the flow ids' do
      expect(enabled_flows).to eq(%w[bl_security])
    end
  end

  context 'when the response is not an object' do
    let!(:request) { stub_enabled_flows(body: %w[bl_security]) }

    it_behaves_like 'failing closed'

    it 'returns no flows' do
      expect(enabled_flows).to eq([])
    end
  end

  context 'with an offline cloud license' do
    before do
      allow(License).to receive(:current).and_return(instance_double(License, offline_cloud_license?: true))
    end

    it 'returns no flows without calling the AI gateway' do
      expect(Gitlab::HTTP).not_to receive(:get)

      expect(enabled_flows).to eq([])
    end
  end

  context 'without a license' do
    before do
      allow(License).to receive(:current).and_return(nil)
    end

    it 'asks the AI gateway' do
      request = stub_enabled_flows

      expect(enabled_flows).to eq(%w[bl_security])
      expect(request).to have_been_requested
    end
  end

  describe '.enabled?' do
    before do
      stub_enabled_flows
    end

    it 'is true only for a flow GitLab enabled' do
      expect(described_class.enabled?('bl_security')).to be(true)
      expect(described_class.enabled?('code_review')).to be(false)
    end
  end
end
