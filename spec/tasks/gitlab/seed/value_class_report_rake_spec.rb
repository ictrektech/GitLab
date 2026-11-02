# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../tooling/quality/value_class_coverage'

RSpec.describe 'gitlab:seed:value_class_report', :silence_output, feature_category: :tooling do
  let(:coverage) { instance_double(Quality::ValueClassCoverage) }

  before do
    Rake.application.rake_require 'tasks/gitlab/seed'
  end

  def finding(table:, column:, seeded: true, missing: %w[glyphs])
    Quality::ValueClassCoverage::Finding.new(
      table: table, column: column, type: :string, seeded: seeded,
      covered: %w[ascii], missing: missing
    )
  end

  def stub_findings(findings)
    allow(Quality::ValueClassCoverage).to receive(:new).and_return(coverage)
    allow(coverage).to receive(:findings).and_return(findings)
  end

  it 'reports the tables it was given' do
    stub_findings([finding(table: 'projects', column: 'name')])

    expect { run_rake_task('gitlab:seed:value_class_report', 'projects') }
      .to output(/Value class coverage for 1 table\(s\).*projects.*name \(string\): missing glyphs/m).to_stdout
  end

  # Rake splits `[a,b]` into separate arguments, so a comma-separated list only arrives in full
  # when `extras` is read as well.
  it 'reads a comma-separated list of tables' do
    stub_findings([])

    expect { run_rake_task('gitlab:seed:value_class_report', 'projects', 'users') }
      .to output(/Value class coverage for 2 table\(s\)/).to_stdout
  end

  it 'says so when none of the names match a table' do
    expect { run_rake_task('gitlab:seed:value_class_report', 'not_a_table') }
      .to output(/No tables to report on/).to_stdout
  end

  it 'omits a column whose rows already cover every class' do
    stub_findings([finding(table: 'projects', column: 'name', missing: [])])

    expect { run_rake_task('gitlab:seed:value_class_report', 'projects') }
      .not_to output(/name \(string\)/).to_stdout
  end

  describe 'unseeded tables' do
    let(:unseeded) { [finding(table: 'projects', column: 'name', seeded: false, missing: %w[null empty])] }

    it 'lists what a named table\'s fixture should produce' do
      stub_findings(unseeded)

      expect { run_rake_task('gitlab:seed:value_class_report', 'projects') }
        .to output(/name \(string\): needs null, empty/).to_stdout
    end

    # Hundreds of tables hold no rows, and the coverage report already flags them as unseeded.
    it 'leaves them out of a sweep of every table' do
      stub_findings(unseeded)
      allow(Gitlab::Database::Dictionary).to receive(:entries)
        .and_return(Gitlab::Database::Dictionary.new([Gitlab::Database::Dictionary.entry('projects')]))

      expect { run_rake_task('gitlab:seed:value_class_report') }
        .not_to output(/name \(string\)/).to_stdout
    end
  end

  it 'names the tables it cannot reach when a schema has no connection' do
    allow(Gitlab::Database).to receive(:schemas_to_base_models).and_return({})

    expect { run_rake_task('gitlab:seed:value_class_report', 'projects') }
      .to output(/projects: no connection for gitlab_schema/).to_stdout
  end

  it 'refuses to scan the tables of a real install' do
    allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

    expect { run_rake_task('gitlab:seed:value_class_report', 'projects') }
      .to output(/only runs in development and test/).to_stdout
  end
end
