# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::TermEntity, feature_category: :consumables_cost_management do
  let(:license) { build_stubbed(:license, starts_at: starts_at, expires_at: expires_at) }
  let(:starts_at) { Date.new(2025, 8, 1) }
  let(:expires_at) { Date.new(2026, 8, 1) }

  subject(:term) { described_class.represent(Utilization::BillableUsage::Exports::Term.new(license)).as_json }

  around do |example|
    travel_to(Time.utc(2026, 10, 1, 9, 0)) { example.run }
  end

  before do
    allow(License).to receive(:current).and_return(license)
  end

  it 'exposes the term' do
    expect(term).to eq(license_id: license.id, start_date: '2025-08-01', end_date: '2026-07-31', current: true)
  end

  context 'with a license that never expires' do
    let(:expires_at) { nil }

    it 'exposes a nil end date' do
      expect(term[:end_date]).to be_nil
    end
  end
end
