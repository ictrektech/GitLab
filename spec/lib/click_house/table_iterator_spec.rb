# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::TableIterator, :click_house, feature_category: :database do
  using RSpec::Parameterized::TableSyntax

  let(:connection) { ClickHouse::Connection.new(:main) }
  let(:table) { 'table_iterator_test' }
  let(:primary_keys) { %i[name id created_at] }
  let(:iterator) { described_class.new(table, primary_keys: primary_keys, connection: connection) }
  let(:create_table_sql) do
    <<~SQL
      CREATE TABLE #{table} (
        name String,
        id UInt64,
        created_at DateTime64(6, 'UTC')
      ) ENGINE = MergeTree
      PRIMARY KEY (#{primary_keys.join(', ')})
      ORDER BY (name, id, created_at)
      SETTINGS index_granularity = 2
    SQL
  end

  before do
    connection.execute(create_table_sql)
  end

  after do
    connection.execute("DROP TABLE IF EXISTS #{table}")
  end

  def insert_rows
    # Two inserts so the ranges have to tile across overlapping parts.
    2.times do |part|
      connection.execute(<<~SQL)
        INSERT INTO #{table} (name, id, created_at)
        SELECT
          concat('name', toString(number % 3)),
          number * 2 + #{part},
          toDateTime64('2024-01-01 00:00:00.123456', 6, 'UTC') + toIntervalMicrosecond(number)
        FROM numbers(20)
      SQL
    end
  end

  def collect(of)
    ranges = []
    ids = []

    iterator.each_range(of: of) do |scope, min_keys, max_keys|
      ranges << [min_keys, max_keys]
      ids.concat(connection.select(scope.select(:id)).pluck('id'))
    end

    [ranges, ids]
  end

  context 'when the table has data' do
    before do
      insert_rows
    end

    it 'visits every row exactly once', :aggregate_failures do
      expected_ids = (0...40).to_a

      [1, 3, 7, 1000].each do |of|
        _, ids = collect(of)

        expect(ids).to match_array(expected_ids)
      end
    end

    it 'yields contiguous ranges bounded by the smallest and largest keys', :aggregate_failures do
      ranges, = collect(5)

      expect(ranges.size).to be > 1
      expect(ranges.first.first).to include(name: 'name0', id: 0)
      expect(ranges.last.last).to include(name: 'name2', id: 35)

      ranges.each_cons(2) do |(_, max_keys), (min_keys, _)|
        expect(max_keys).to eq(min_keys)
      end

      expect(ranges.first.first.keys).to eq(primary_keys)
      expect(ranges.first.first[:created_at]).to be_a(Time)
    end

    it 'skips rows inserted above the largest key during the iteration' do
      ids = []

      iterator.each_range(of: 5).with_index do |(scope, *), i|
        connection.execute("INSERT INTO #{table} (name, id) VALUES ('zzz', 1000)") if i == 0
        ids.concat(connection.select(scope.select(:id)).pluck('id'))
      end

      expect(ids).to match_array((0...40).to_a)
    end

    it 'skips rows inserted between reading the edge keys and the boundaries', :aggregate_failures do
      allow(iterator).to receive(:find_edge_key).and_wrap_original do |method, direction|
        method.call(direction).tap do
          next unless direction == :desc

          connection.execute(<<~SQL)
            INSERT INTO #{table} (name, id)
            SELECT if(number % 2 = 0, 'aaa', 'zzz'), number + 1000 FROM numbers(40)
          SQL
        end
      end

      ranges, ids = collect(5)

      expect(ids).to match_array((0...40).to_a)
      expect(ranges.first.first).to include(name: 'name0', id: 0)
      expect(ranges.last.last).to include(name: 'name2', id: 35)
      expect(ranges.flatten.pluck(:name)).to all(start_with('name'))
    end

    context 'with a single column primary key' do
      let(:primary_keys) { %i[name] }

      it 'visits every row exactly once' do
        _, ids = collect(3)

        expect(ids).to match_array((0...40).to_a)
      end
    end
  end

  context 'when the index omits trailing primary key columns' do
    let(:primary_keys) { %i[id value] }
    let(:create_table_sql) do
      <<~SQL
        CREATE TABLE #{table} (id UInt64, value Int64)
        ENGINE = MergeTree
        ORDER BY (id, value)
        SETTINGS index_granularity = 2
      SQL
    end

    before do
      # Unique ids make ClickHouse store only `id` in the index, so `value` reads back as 0.
      connection.execute("INSERT INTO #{table} SELECT number, -1 - number FROM numbers(20)")
    end

    it 'visits every row exactly once' do
      _, ids = collect(3)

      expect(ids).to match_array((0...20).to_a)
    end
  end

  context 'when no block is given' do
    before do
      insert_rows
    end

    it 'returns an enumerator yielding the same ranges' do
      with_block = []
      iterator.each_range(of: 5) { |_scope, min_keys, max_keys| with_block << [min_keys, max_keys] }

      enumerator = iterator.each_range(of: 5)

      expect(enumerator).to be_a(Enumerator)
      expect(enumerator.map { |_scope, min_keys, max_keys| [min_keys, max_keys] }).to eq(with_block)
    end
  end

  context 'when the table is empty' do
    it 'yields nothing' do
      expect { |b| iterator.each_range(of: 10, &b) }.not_to yield_control
    end
  end

  describe 'generated range condition' do
    before do
      insert_rows
    end

    it 'expands the tuple comparison so the primary key index can be used', :aggregate_failures do
      sqls = []
      iterator.each_range(of: 5) { |scope, *| sqls << scope.to_sql }

      expect(sqls.second).to include(
        "`#{table}`.`name` > CAST(",
        "`#{table}`.`name` = CAST(",
        "`#{table}`.`created_at` >= CAST(",
        "`#{table}`.`created_at` < CAST(",
        "'DateTime64(6, ''UTC'')'"
      )
      expect(sqls.last).to include("`#{table}`.`created_at` <= CAST(")
      expect(sqls[0...-1]).to all(exclude('<= CAST('))
    end
  end

  describe 'timestamp primary key columns' do
    let(:primary_keys) { %i[ts id] }
    let(:create_table_sql) do
      <<~SQL
        CREATE TABLE #{table} (ts #{column_type}, id UInt64)
        ENGINE = MergeTree
        ORDER BY (ts, id)
      SQL
    end

    before do
      connection.execute("INSERT INTO #{table} SELECT toDateTime('2024-10-27 00:00:00', 'UTC'), number FROM numbers(3)")
    end

    where(:column_type, :error) do
      "DateTime64(6, 'UTC')" | nil
      "DateTime('UTC')" | nil
      "DateTime64(6, 'Europe/Berlin')" | /column ts must use the UTC timezone/
      "DateTime('Europe/Berlin')" | /column ts must use the UTC timezone/
      'DateTime64(6)' | /column ts must use the UTC timezone/
      'DateTime' | /column ts must use the UTC timezone/
    end

    with_them do
      it 'only accepts the UTC timezone' do
        each_range = -> { iterator.each_range(of: 10) { nil } }

        if error
          expect(&each_range).to raise_error(ArgumentError, error)
        else
          expect(&each_range).not_to raise_error
        end
      end
    end
  end

  describe 'argument validation' do
    it 'raises when primary keys are empty' do
      expect { described_class.new(table, primary_keys: [], connection: connection) }
        .to raise_error(ArgumentError, /primary_keys/)
    end

    it 'raises when the batch size is not positive' do
      expect { iterator.each_range(of: 0) { nil } }.to raise_error(ArgumentError, /batch size/)
    end
  end
end
