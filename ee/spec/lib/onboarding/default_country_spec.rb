# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::DefaultCountry, feature_category: :onboarding do
  let(:country_code) { 'NL' }
  let(:headers) { { 'Cf-Ipcountry' => country_code } }
  let(:request) { instance_double(ActionDispatch::Request, headers: headers) }

  subject(:default_country) { described_class.new(request) }

  describe '#code' do
    it 'returns the country Cloudflare resolved' do
      expect(default_country.code).to eq('NL')
    end

    context 'when the header is absent' do
      let(:headers) { {} }

      it { expect(default_country.code).to be_nil }
    end

    context 'when Cloudflare could not resolve the IP' do
      let(:country_code) { 'XX' }

      it { expect(default_country.code).to be_nil }
    end

    context 'when the resolved country is not offered by the selector' do
      let(:country_code) { 'CN' }

      it { expect(default_country.code).to be_nil }
    end
  end

  describe '#outcome_for' do
    context 'when a default was offered' do
      it 'reports acceptance when the user kept it' do
        expect(default_country.outcome_for('NL')).to eq(described_class::ACCEPTED)
      end

      it 'reports a change when the user picked something else' do
        expect(default_country.outcome_for('DE')).to eq(described_class::CHANGED)
      end

      it 'reports a change when the user cleared it' do
        expect(default_country.outcome_for('')).to eq(described_class::CHANGED)
      end
    end

    context 'when no default was offered' do
      let(:country_code) { 'XX' }

      it 'reports not_offered regardless of what the user selected' do
        expect(default_country.outcome_for('DE')).to eq(described_class::NOT_OFFERED)
      end
    end
  end
end
