# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Session::Settings::TransactionTimeout, :delete, feature_category: :database do
  let(:connection) { ApplicationRecord.connection }

  def current_timeout
    connection.select_value('SHOW transaction_timeout')
  end

  around do |example|
    next example.run unless Gitlab::Database::TransactionTimeout.supported?(connection)

    begin
      original = current_timeout
      connection.execute("SET transaction_timeout TO '15s'")
      example.run
    ensure
      connection.execute("SET transaction_timeout TO #{connection.quote(original)}")
    end
  end

  describe '.with' do
    context 'when the database supports transaction_timeout' do
      before do
        skip 'transaction_timeout requires PostgreSQL 17 or later' unless
          Gitlab::Database::TransactionTimeout.supported?(connection)
      end

      it 'sets transaction_timeout inside the block and restores it afterwards' do
        described_class.with(connection, '2h') do
          expect(current_timeout).to eq('2h')
        end

        expect(current_timeout).to eq('15s')
      end

      it 'disables transaction_timeout for a zero timeout' do
        described_class.with(connection, 0) do
          expect(current_timeout).to eq('0')
        end

        expect(current_timeout).to eq('15s')
      end

      it 'restores transaction_timeout when the block raises' do
        expect { described_class.with(connection, 0) { raise 'boom' } }.to raise_error('boom')

        expect(current_timeout).to eq('15s')
      end

      it 'returns the value of the block' do
        expect(described_class.with(connection, 0) { :result }).to eq(:result)
      end
    end

    context 'when the database is older than PostgreSQL 17' do
      before do
        allow(connection).to receive(:database_version).and_return(16_00_00)
      end

      it 'yields without reading or setting transaction_timeout' do
        allow(connection).to receive(:exec_query).and_call_original
        allow(connection).to receive(:select_value).and_call_original
        expect(connection).not_to receive(:exec_query).with(/transaction_timeout/)
        expect(connection).not_to receive(:select_value).with(/transaction_timeout/)

        expect(described_class.with(connection, 0) { :result }).to eq(:result)
      end
    end
  end
end
