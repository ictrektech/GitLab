# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Migrations::TimeoutHelpers, feature_category: :database do
  let(:model) do
    ActiveRecord::Migration.new.extend(described_class)
  end

  describe '#disable_statement_timeout' do
    it 'disables statement timeouts to current transaction only' do
      expect(model).to receive(:execute).with('SET LOCAL statement_timeout TO 0')

      model.disable_statement_timeout
    end

    it 'disables the transaction timeout for the current transaction only' do
      allow(model).to receive(:execute)
      expect(Gitlab::Database::TransactionTimeout).to receive(:disable).with(model.connection, local: true)

      model.disable_statement_timeout
    end

    # this specs runs without an enclosing transaction (:delete truncation method for db_cleaner)
    context 'with real environment', :delete do
      let(:connection) { model.connection }
      let(:transaction_timeout_supported) { Gitlab::Database::TransactionTimeout.supported?(connection) }

      def current_timeout(name)
        connection.select_value("SHOW #{name}")
      end

      # The session values stand in for what database.yml sets, which a RESET would drop back to the server default.
      around do |example|
        original_statement_timeout = current_timeout('statement_timeout')
        original_transaction_timeout = current_timeout('transaction_timeout') if transaction_timeout_supported
        connection.execute("SET statement_timeout TO '20s'")
        connection.execute("SET transaction_timeout TO '1h'") if transaction_timeout_supported
        example.run
      ensure
        connection.execute("SET statement_timeout TO #{connection.quote(original_statement_timeout)}")

        if transaction_timeout_supported
          connection.execute("SET transaction_timeout TO #{connection.quote(original_transaction_timeout)}")
        end
      end

      it 'defines statement to 0 only for current transaction' do
        expect(current_timeout('statement_timeout')).to eq('20s')

        connection.transaction do
          model.disable_statement_timeout
          expect(current_timeout('statement_timeout')).to eq('0')
        end

        expect(current_timeout('statement_timeout')).to eq('20s')
      end

      context 'when passing a block' do
        it 'disables statement timeouts on session level and executes the block' do
          expect { |block| model.disable_statement_timeout(&block) }.to yield_control

          model.disable_statement_timeout do
            expect(current_timeout('statement_timeout')).to eq('0')

            connection.transaction do
              expect(current_timeout('statement_timeout')).to eq('0')
            end

            expect(current_timeout('statement_timeout')).to eq('0')
          end
        end

        it 'restores the statement timeout the session had rather than the server default' do
          model.disable_statement_timeout { model.execute('SELECT 1') }

          expect(current_timeout('statement_timeout')).to eq('20s')
        end

        it 'returns the value of the block' do
          expect(model.disable_statement_timeout { :result }).to eq(:result)
        end

        it 'restores the statement timeout when the block raises' do
          expect { model.disable_statement_timeout { raise 'boom' } }.to raise_error('boom')

          expect(current_timeout('statement_timeout')).to eq('20s')
        end

        it 'restores the outer value after a nested call' do
          Gitlab::Database::Session::Settings::StatementTimeout.with(connection, '30s') do
            model.disable_statement_timeout do
              model.disable_statement_timeout { expect(current_timeout('statement_timeout')).to eq('0') }

              expect(current_timeout('statement_timeout')).to eq('0')
            end

            expect(current_timeout('statement_timeout')).to eq('30s')
          end
        end

        context 'when the statement_timeout is already disabled' do
          before do
            connection.execute('SET statement_timeout TO 0')
          end

          it 'keeps it disabled after the block' do
            model.disable_statement_timeout { expect(current_timeout('statement_timeout')).to eq('0') }

            expect(current_timeout('statement_timeout')).to eq('0')
          end
        end

        context 'with a transaction open' do
          it 'lifts the timeouts for that transaction only with SET LOCAL' do
            allow(model).to receive(:execute).and_call_original
            expect(model).to receive(:execute).with('SET LOCAL statement_timeout TO 0').and_call_original
            expect(model).not_to receive(:execute).with(/RESET/)

            connection.transaction do
              model.disable_statement_timeout do
                expect(current_timeout('statement_timeout')).to eq('0')
                expect(current_timeout('transaction_timeout')).to eq('0') if transaction_timeout_supported
              end

              expect(current_timeout('statement_timeout')).to eq('0')
            end

            expect(current_timeout('statement_timeout')).to eq('20s')
            expect(current_timeout('transaction_timeout')).to eq('1h') if transaction_timeout_supported
          end

          it 'does not raise a transaction open error' do
            connection.transaction do
              expect { |block| model.disable_statement_timeout(&block) }.to yield_control
            end
          end

          it 'raises a database error from the block as itself, not as a failed transaction error' do
            expect do
              connection.transaction do
                model.disable_statement_timeout { model.execute('SELECT 1/0') }
              end
            end.to raise_error(ActiveRecord::StatementInvalid, /division by zero/)

            expect(current_timeout('statement_timeout')).to eq('20s')
          end

          it 'puts the values back when the transaction rolls back' do
            allow(model).to receive(:execute).and_call_original
            expect(model).to receive(:execute).with('SET LOCAL statement_timeout TO 0').and_call_original

            connection.transaction do
              model.disable_statement_timeout { model.execute('SELECT 1') }

              raise ActiveRecord::Rollback
            end

            expect(current_timeout('statement_timeout')).to eq('20s')
            expect(current_timeout('transaction_timeout')).to eq('1h') if transaction_timeout_supported
          end
        end

        context 'when the database supports transaction_timeout' do
          before do
            skip 'transaction_timeout requires PostgreSQL 17 or later' unless transaction_timeout_supported
          end

          it 'disables the transaction timeout inside the block and restores the session value' do
            model.disable_statement_timeout do
              expect(current_timeout('transaction_timeout')).to eq('0')
            end

            expect(current_timeout('transaction_timeout')).to eq('1h')
          end

          it 'restores the transaction timeout when the block raises' do
            expect { model.disable_statement_timeout { raise 'boom' } }.to raise_error('boom')

            expect(current_timeout('transaction_timeout')).to eq('1h')
          end

          it 'restores the outer transaction timeout after a nested call' do
            Gitlab::Database::Session::Settings::TransactionTimeout.with(connection, '2h') do
              model.disable_statement_timeout { model.disable_statement_timeout { model.execute('SELECT 1') } }

              expect(current_timeout('transaction_timeout')).to eq('2h')
            end
          end

          context 'when the statement_timeout is already disabled' do
            before do
              connection.execute('SET statement_timeout TO 0')
            end

            it 'lifts the transaction timeout around the block' do
              model.disable_statement_timeout do
                expect(current_timeout('transaction_timeout')).to eq('0')
              end

              expect(current_timeout('transaction_timeout')).to eq('1h')
            end
          end
        end

        context 'when the database is older than PostgreSQL 17' do
          before do
            allow(connection).to receive(:database_version).and_return(16_00_00)
          end

          it 'lifts only the statement timeout and never reads or sets transaction_timeout' do
            allow(connection).to receive(:exec_query).and_call_original
            allow(connection).to receive(:select_value).and_call_original
            expect(connection).not_to receive(:exec_query).with(/transaction_timeout/)
            expect(connection).not_to receive(:select_value).with(/transaction_timeout/)

            model.disable_statement_timeout { expect(current_timeout('statement_timeout')).to eq('0') }

            expect(current_timeout('statement_timeout')).to eq('20s')
          end
        end
      end
    end
  end
end
