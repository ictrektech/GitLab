# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SelfManaged::TrialAvailabilityService, feature_category: :acquisition do
  let(:portal_url) { 'https://customers.example.com' }
  let(:availability_url) { "#{portal_url}/trials/self_managed/ultimates/availability" }
  let(:query) { { gitlab_version: Gitlab::VERSION } }

  subject(:execute) { described_class.execute }

  before do
    stub_env('CUSTOMER_PORTAL_URL', portal_url)
  end

  def stub_availability_request(status:, body: nil)
    stub_request(:get, availability_url)
      .with(query: query)
      .to_return(
        status: status,
        body: body,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def availability_request
    a_request(:get, availability_url).with(query: query)
  end

  describe '#execute' do
    context 'when CustomersDot reports self-service trials are available' do
      before do
        stub_availability_request(status: 200, body: { available: true }.to_json)
      end

      it { is_expected.to be(true) }

      it 'asks CustomersDot on every call' do
        described_class.execute
        described_class.execute

        expect(availability_request).to have_been_made.twice
      end
    end

    context 'when CustomersDot reports self-service trials are unavailable' do
      before do
        stub_availability_request(status: 200, body: { available: false }.to_json)
      end

      it { is_expected.to be(false) }

      it 'asks CustomersDot on every call' do
        described_class.execute
        described_class.execute

        expect(availability_request).to have_been_made.twice
      end
    end

    context 'when the response omits the availability key' do
      before do
        stub_availability_request(status: 200, body: { something_else: true }.to_json)
      end

      it { is_expected.to be(false) }
    end

    context 'when availability is returned as a string rather than a boolean' do
      before do
        stub_availability_request(status: 200, body: { available: 'true' }.to_json)
      end

      it { is_expected.to be(false) }
    end

    context 'when the endpoint is not deployed yet' do
      before do
        stub_availability_request(status: 404)
      end

      it { is_expected.to be(false) }
    end

    context 'when CustomersDot cannot be reached' do
      before do
        stub_request(:get, availability_url).with(query: query).to_timeout
      end

      it { is_expected.to be(false) }
    end

    context 'when CustomersDot returns an unexpected status' do
      before do
        stub_availability_request(status: 500)
      end

      it { is_expected.to be(false) }
    end

    context 'when CustomersDot returns a body that is not a JSON object' do
      before do
        stub_availability_request(status: 200, body: '[]')
      end

      it { is_expected.to be(false) }
    end

    context 'when CustomersDot returns an unparseable body' do
      before do
        stub_availability_request(status: 200, body: 'not json')
      end

      it { is_expected.to be(false) }
    end

    context 'when a failed request is followed by a successful one' do
      before do
        stub_request(:get, availability_url)
          .with(query: query)
          .to_timeout
          .then
          .to_return(
            status: 200,
            body: { available: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'recovers on the next call instead of serving the earlier failure' do
        expect(described_class.execute).to be(false)
        expect(described_class.execute).to be(true)
      end
    end
  end
end
