# frozen_string_literal: true

RSpec.shared_examples 'a Zoekt worker deferring on autovacuum of' do |tables, delay_by: 10.minutes|
  it 'defers only on the tables it writes' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main, tables: tables, delay_by: delay_by
    )
  end
end
