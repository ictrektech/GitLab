# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::Samplers::PgAshSampler, feature_category: :database do
  subject(:sample) { described_class.new.sample }

  it_behaves_like 'metrics sampler', 'PG_ASH_SAMPLER'

  describe '#sample' do
    let(:installer) { instance_double(Gitlab::Database::PgAsh::Installer, installed?: true) }
    let(:db_sampler) { instance_double(Gitlab::Database::PgAsh::Sampler, execute: nil) }

    before do
      stub_application_setting(pg_ash_sampling_enabled: true)

      allow(Gitlab::Database::PgAsh::Installer).to receive(:new).and_return(installer)
      allow(Gitlab::Database::PgAsh::Sampler).to receive(:new).and_return(db_sampler)
    end

    it 'runs the database sampler' do
      sample

      expect(db_sampler).to have_received(:execute)
    end

    context 'when sampling is disabled' do
      before do
        stub_application_setting(pg_ash_sampling_enabled: false)
      end

      it 'does nothing' do
        expect(Gitlab::Database::PgAsh::Sampler).not_to receive(:new)

        sample
      end
    end

    context 'when the database is read-only' do
      before do
        allow(Gitlab::Database).to receive(:read_only?).and_return(true)
      end

      it 'does nothing' do
        expect(Gitlab::Database::PgAsh::Sampler).not_to receive(:new)

        sample
      end
    end

    context 'when pg_ash is not installed' do
      let(:installer) { instance_double(Gitlab::Database::PgAsh::Installer, installed?: false) }

      it 'does nothing' do
        expect(Gitlab::Database::PgAsh::Sampler).not_to receive(:new)

        sample
      end
    end

    context 'when a check raises' do
      let(:error) { ActiveRecord::ConnectionNotEstablished.new('connection refused') }

      before do
        allow(installer).to receive(:installed?).and_raise(error)
      end

      it 'tracks the error and keeps the sampler thread running', :aggregate_failures do
        sampler = described_class.new

        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)
        expect(sampler).not_to receive(:stop)

        sampler.safe_sample
      end
    end
  end
end
