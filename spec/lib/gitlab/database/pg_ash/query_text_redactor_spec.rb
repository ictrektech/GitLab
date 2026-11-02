# frozen_string_literal: true

require 'fast_spec_helper'
require 'pg_query'

RSpec.describe Gitlab::Database::PgAsh::QueryTextRedactor, feature_category: :database do
  describe '.redact' do
    subject(:redacted) { described_class.redact(text, limit: 1_000) }

    context 'with a query' do
      where(:text) do
        [
          "SELECT * FROM t WHERE a = 'secret'",
          "INSERT INTO t (a) VALUES ('secret')",
          "UPDATE t SET a = 'secret'",
          "DELETE FROM t WHERE a = 'secret'",
          "MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET a = 'secret'"
        ]
      end

      with_them do
        it 'replaces literal values with placeholders #security' do
          expect(redacted).to eq(text.sub("'secret'", '$1'))
        end
      end
    end

    context 'with a transaction command' do
      where(:text, :shown) do
        [
          %w[BEGIN BEGIN],
          %w[COMMIT COMMIT],
          ["PREPARE TRANSACTION 'secret'", 'PREPARE TRANSACTION $1']
        ]
      end

      with_them do
        it 'shows it, because COMMIT can carry load while it waits for the WAL' do
          expect(redacted).to eq(shown)
        end
      end
    end

    context 'with a schema change or maintenance statement' do
      where(:text, :shown) do
        [
          ["ALTER TABLE t ADD c text DEFAULT 'secret'", 'ALTER TABLE t ADD c text DEFAULT $1'],
          ["ALTER FOREIGN TABLE t OPTIONS (ADD password 'secret')", 'ALTER FOREIGN TABLE t OPTIONS (ADD password $1)'],
          ['CREATE INDEX i ON t (a) WHERE a > 42', 'CREATE INDEX i ON t (a) WHERE a > $1'],
          ['CREATE TABLE c AS SELECT $1, 7', 'CREATE TABLE c AS SELECT $1, $2'],
          ['LOCK TABLE t IN ACCESS EXCLUSIVE MODE', 'LOCK TABLE t IN ACCESS EXCLUSIVE MODE'],
          ['COPY t TO STDOUT', 'COPY t TO STDOUT']
        ]
      end

      with_them do
        it 'replaces every value #security' do
          expect(redacted).to eq(shown)
        end
      end
    end

    context 'with a value in each form the scanner reads' do
      where(:value, :shown) do
        [
          ["E'secret'", '$1'],
          ["U&'secret' UESCAPE '!'", '$1 UESCAPE $2'],
          ['$q$secret$q$', '$1'],
          ["B'1010'", '$1'],
          ["X'ff'", '$1'],
          ['1.5', '$1']
        ]
      end

      let(:text) { "ALTER TABLE t ALTER c SET DEFAULT #{value}" }

      with_them do
        it 'replaces it #security' do
          expect(redacted).to eq("ALTER TABLE t ALTER c SET DEFAULT #{shown}")
        end
      end
    end

    context 'with comments' do
      let(:text) { %(SELECT "é", $1/* a */FROM t -- token 'b') }

      it 'drops them, keeping the words around them apart #security' do
        expect(redacted).to eq('SELECT "é", $1 FROM t')
      end
    end

    context 'with text over the limit' do
      let(:text) { %(SELECT "#{'é' * 1_200}" FROM t) }

      it 'caps it by characters, so it stays valid UTF-8' do
        expect(redacted).to eq(text.truncate(1_000))
      end
    end

    context 'with another statement' do
      where(:text) do
        [
          "ALTER ROLE gitlab PASSWORD 'secret'",
          'ALTER ROLE gitlab SET app.key = secret',
          'SET app.key = secret',
          "COPY t FROM PROGRAM 'curl --header \"Authorization: Bearer secret\"'",
          "COPY t TO '/backups/secret.csv'",
          'COPY t FROM STDIN WITH (NULL "secret")',
          'CREATE TRIGGER tr AFTER INSERT ON t EXECUTE FUNCTION f(secret)',
          'CREATE TRIGGER tr AFTER INSERT ON t EXECUTE FUNCTION f("secret")',
          "CREATE SERVER s FOREIGN DATA WRAPPER postgres_fdw OPTIONS (password 'secret')",
          "SELECT 1; ALTER SYSTEM SET a = 'secret'"
        ]
      end

      with_them do
        it 'shows no text, because pg_stat_statements keeps it as typed #security' do
          expect(redacted).to be_nil
        end
      end
    end

    context 'with a backslash' do
      # With standard_conforming_strings off, PostgreSQL reads everything after DEFAULT as one string.
      let(:text) { "ALTER TABLE t ALTER c SET DEFAULT 'a\\'::text || secret --'" }

      it 'shows no text, because the session may have read the string differently #security' do
        expect(redacted).to be_nil
      end
    end

    context 'with text that does not parse' do
      let(:text) { '<insufficient privilege>' }

      it { is_expected.to be_nil }
    end
  end
end
