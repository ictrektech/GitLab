# frozen_string_literal: true

require 'fast_spec_helper'

require_relative '../../../tooling/quality/value_class_coverage'

RSpec.describe Quality::ValueClassCoverage, feature_category: :tooling do
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

  subject(:findings) { described_class.new(%w[widgets], connection: connection).findings }

  def column(name, type, null: true, array: false)
    double(name: name, type: type, null: null, array?: array) # rubocop:disable RSpec/VerifiedDoubles -- column structs vary by adapter
  end

  # Class aliases are positional, so the counts are listed in the order the classes are checked:
  # `null` first for a nullable column, then the rule set for its type.
  def check_constraint(expression)
    double(expression: expression) # rubocop:disable RSpec/VerifiedDoubles -- constraint structs vary by adapter
  end

  def stub_table(columns, *counts, rows: 2, primary_key: 'id', check_constraints: [])
    allow(connection).to receive(:table_exists?).with('widgets').and_return(true)
    allow(connection).to receive(:primary_key).with('widgets').and_return(primary_key)
    allow(connection).to receive(:check_constraints).with('widgets').and_return(check_constraints)
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote_column_name) { |name| %("#{name}") }
    allow(connection).to receive(:columns).with('widgets').and_return(columns)

    counted = counts.each_with_index.to_h { |value, index| ["c#{index}", value] }
    allow(connection).to receive(:select_one).and_return({ 'row_count' => rows }.merge(counted))
  end

  def finding_for(name)
    findings.find { |finding| finding.column == name }
  end

  describe '#findings' do
    it 'returns nothing for a table that is absent from the schema' do
      allow(connection).to receive(:table_exists?).with('widgets').and_return(false)

      expect(findings).to be_empty
    end

    it 'splits a column into the classes its rows cover and the ones they do not' do
      stub_table([column('title', :string)], 0, 0, 2, 0)

      expect(finding_for('title').covered).to eq(%w[ascii])
      expect(finding_for('title').missing).to contain_exactly('null', 'empty', 'glyphs')
    end

    it 'marks a column whose rows cover every class as complete' do
      stub_table([column('title', :string)], 1, 1, 1, 1)

      expect(finding_for('title')).to be_complete
    end

    # A NOT NULL column can never hold a null, so reporting it would be a gap nobody can close.
    it 'offers the null class only for a nullable column' do
      stub_table([column('title', :string, null: false)], 0, 2, 0)

      expect(finding_for('title').missing).not_to include('null')
    end

    # `add_not_null_constraint` leaves the column nullable in the catalog, so the check constraint
    # is the only thing saying a null is rejected.
    it 'withholds the null class from a column a check constraint forbids a null in' do
      stub_table([column('project_id', :integer)], 2,
        check_constraints: [check_constraint('project_id IS NOT NULL')])

      expect(finding_for('project_id').missing).to be_empty
    end

    it 'ignores check constraints that forbid no class' do
      stub_table([column('title', :string)], 0, 0, 2, 0,
        check_constraints: [check_constraint('char_length(title) <= 255')])

      expect(finding_for('title').missing).to include('null')
    end

    it 'withholds negative from a column constrained to zero or above' do
      stub_table([column('size', :integer, null: false)], 0, 2,
        check_constraints: [check_constraint('size >= 0')])

      expect(finding_for('size').missing).to contain_exactly('zero')
    end

    # Postgres quotes a column name that collides with a keyword, so the pattern never sees a
    # bare `position`.
    it 'withholds a class named in a constraint that quotes the column' do
      stub_table([column('position', :integer, null: false)], 0, 2,
        check_constraints: [check_constraint('"position" >= 0')])

      expect(finding_for('position').missing).to contain_exactly('zero')
    end

    # `> 0` puts zero out of reach as well as every negative.
    it 'withholds both zero and negative from a column constrained above zero' do
      stub_table([column('size', :integer, null: false)], 2,
        check_constraints: [check_constraint('size > 0')])

      expect(finding_for('size').missing).to be_empty
    end

    # The value may still be reachable through the other side of the expression.
    it 'keeps every class when the constraint is a compound expression' do
      stub_table([column('size', :integer, null: false)], 0, 0, 0,
        check_constraints: [check_constraint('(size > 0) OR ((size = 0) AND (state = 255))')])

      expect(finding_for('size').missing).to contain_exactly('zero', 'positive', 'negative')
    end

    it 'treats an array column by cardinality rather than as its element type' do
      stub_table([column('mentioned_users_ids', :integer, array: true)], 1, 0, 1)

      expect(finding_for('mentioned_users_ids').missing).to eq(%w[empty])
    end

    it 'treats the primary key and integer foreign keys as identifiers' do
      stub_table([column('id', :integer, null: false), column('project_id', :integer)], 2, 0, 2)

      expect(finding_for('id').missing).to be_empty
      expect(finding_for('project_id').missing).to eq(%w[null])
    end

    # A partitioned table's key spans several columns, and `primary_key` returns them as an array.
    it 'treats every column of a composite primary key as an identifier' do
      stub_table([column('id', :integer, null: false), column('partition_id', :integer, null: false)],
        2, 2, primary_key: %w[id partition_id])

      expect(finding_for('id').missing).to be_empty
      expect(finding_for('partition_id').missing).to be_empty
    end

    # `commit_id` holds a SHA, so its empty and multibyte shapes still matter.
    it 'does not treat a non-integer column as an identifier because it ends in _id' do
      stub_table([column('commit_id', :string)], 0, 0, 2, 0)

      expect(finding_for('commit_id').missing).to contain_exactly('null', 'empty', 'glyphs')
    end

    it 'applies the integer classes to a column that is not an identifier' do
      stub_table([column('weight', :integer)], 2, 0, 0, 0)

      expect(finding_for('weight').missing).to contain_exactly('zero', 'positive', 'negative')
    end

    it 'skips a column type that has no rules' do
      stub_table([column('token', :binary)])

      expect(findings).to be_empty
    end

    it 'marks a table that holds no rows as unseeded rather than dropping it' do
      stub_table([column('title', :string)], 0, 0, 0, 0, rows: 0)

      expect(finding_for('title')).to be_unseeded
      expect(finding_for('title').missing).to contain_exactly('null', 'empty', 'ascii', 'glyphs')
    end
  end

  # The counts are stubbed by position, so nothing else here would notice a broken predicate.
  describe 'the counting query' do
    def sql_for(columns)
      captured = nil
      stub_table(columns)
      allow(connection).to receive(:select_one) do |sql|
        captured = sql
        { 'row_count' => 0 }
      end
      findings

      captured
    end

    it 'detects multibyte text by comparing byte length against character length' do
      expect(sql_for([column('title', :string)]))
        .to include(%(count(*) FILTER (WHERE octet_length("title") <> char_length("title"))))
    end

    it 'measures an array by cardinality' do
      expect(sql_for([column('ids', :integer, array: true)]))
        .to include(%(count(*) FILTER (WHERE cardinality("ids") = 0)))
    end

    # A `json` column has no equality operator against `jsonb`, so the cast keeps the predicate
    # valid for both types.
    it 'casts before comparing a json document' do
      expect(sql_for([column('payload', :jsonb)]))
        .to include(%("payload"::jsonb IN ('{}'::jsonb, '[]'::jsonb)))
    end

    it 'counts every class in one query over the table' do
      sql = sql_for([column('archived', :boolean, null: false)])

      expect(sql).to start_with('SELECT count(*) AS row_count')
      expect(sql).to end_with('FROM "widgets"')
    end
  end

  describe 'Finding#summary' do
    it 'lists the missing classes first so the gap is the readable part' do
      stub_table([column('title', :string)], 1, 0, 1, 0)

      expect(finding_for('title').summary).to eq('title (string): missing empty, glyphs (covers null, ascii)')
    end

    it 'reports what a complete column covers' do
      stub_table([column('archived', :boolean, null: false)], 1, 1)

      expect(finding_for('archived').summary).to eq('archived (boolean): covers true, false')
    end

    # With no rows there is nothing to have missed, so the classes read as what to write.
    it 'reads as a specification when the table is unseeded' do
      stub_table([column('title', :string)], 0, 0, 0, 0, rows: 0)

      expect(finding_for('title').summary).to eq('title (string): needs null, empty, ascii, glyphs')
    end
  end
end
