# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Auth::VisitorLocation, feature_category: :onboarding do
  let(:country_code) { 'DE' }
  let(:headers) { { 'Cf-Ipcountry' => country_code } }
  let(:request) { instance_double(ActionDispatch::Request, headers: headers) }

  subject(:request_info) { described_class.new(request) }

  describe '#country_code' do
    it 'returns the alpha-2 code Cloudflare resolved' do
      expect(request_info.country_code).to eq('DE')
    end

    context 'when the header is absent' do
      let(:headers) { {} }

      it { expect(request_info.country_code).to be_nil }
    end

    context 'when the header is blank' do
      let(:country_code) { '' }

      it { expect(request_info.country_code).to be_nil }
    end

    ::EE::Gitlab::Auth::VisitorLocation::UNRESOLVED_COUNTRY_CODES.each do |unresolved|
      context "when Cloudflare could not resolve the IP (#{unresolved})" do
        let(:country_code) { unresolved }

        it { expect(request_info.country_code).to be_nil }
      end
    end
  end
end
