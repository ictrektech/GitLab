# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ml::CandidatesCsvPresenter, feature_category: :mlops do
  # rubocop:disable RSpec/FactoryBot/AvoidCreate
  let_it_be(:project) { create(:project) }
  let_it_be(:experiment) { create(:ml_experiments, user_id: project.creator, project: project) }

  let_it_be(:candidate0) do
    create(:ml_candidates, experiment: experiment, user: project.creator,
      project: project, start_time: 1234, end_time: 5678).tap do |c|
      c.params.create!([{ name: 'param1', value: 'p1' }, { name: 'param2', value: 'p2' }])
      c.metrics.create!(
        [{ name: 'metric1', value: 0.1 }, { name: 'metric2', value: 0.2 }, { name: 'metric3', value: 0.3 }]
      )
    end
  end

  let_it_be(:candidate1) do
    create(:ml_candidates, experiment: experiment, user: project.creator, name: 'candidate1',
      project: project, start_time: 1111, end_time: 2222).tap do |c|
      c.params.create([{ name: 'param2', value: 'p3' }, { name: 'param3', value: 'p4' }])
      c.metrics.create!(name: 'metric3', value: 0.4)
    end
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate

  describe '.present' do
    subject { described_class.new(::Ml::Candidate.where(id: [candidate0.id, candidate1.id]), project: project).present }

    it 'generates header row correctly' do
      expected_header = %w[project_id experiment_iid candidate_iid name external_id start_time end_time param1 param2
        param3 metric1 metric2 metric3].join(',')
      header = subject.split("\n")[0]

      expect(header).to eq(expected_header)
    end

    it 'generates the first row correctly' do
      expected_row = [
        candidate0.project_id,
        1, # experiment.iid
        1, # candidate0.internal_id
        '', # candidate0 has no name, column is empty
        candidate0.eid,
        candidate0.start_time,
        candidate0.end_time,
        candidate0.params[0].value,
        candidate0.params[1].value,
        '', # candidate0 has no param3, column is empty
        candidate0.metrics[0].value,
        candidate0.metrics[1].value,
        candidate0.metrics[2].value
      ].map(&:to_s)

      row = subject.split("\n")[1].split(",")

      expect(row).to match_array(expected_row)
    end

    it 'generates the second row correctly' do
      expected_row = [
        candidate1.project_id,
        1, # experiment.iid
        2, # candidate1.internal_id
        'candidate1',
        candidate1.eid,
        candidate1.start_time,
        candidate1.end_time,
        '', # candidate1 has no param1, column is empty
        candidate1.params[0].value,
        candidate1.params[1].value,
        '', # candidate1 has no metric1, column is empty
        '', # candidate1 has no metric2, column is empty
        candidate1.metrics[0].value
      ].map(&:to_s)

      row = subject.split("\n")[2].split(",")

      expect(row).to match_array(expected_row)
    end

    context 'when metrics are logged at different rates' do
      # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the presenter reads the metrics from the database
      let_it_be(:history_experiment) { create(:ml_experiments, project: project) }
      let_it_be(:history_candidates) do
        create_list(:ml_candidates, 2, experiment: history_experiment, project: project).each_with_index do |c, i|
          c.metrics.create!(name: 'loss', value: 10 * i, step: 0)
          c.metrics.create!(name: 'accuracy', value: (10 * i) + 0.5, step: 0)
          c.metrics.create!(name: 'loss', value: (10 * i) + 1, step: 1)
          c.metrics.create!(name: 'loss', value: (10 * i) + 2, step: 2)
        end
      end
      # rubocop:enable RSpec/FactoryBot/AvoidCreate

      def present_csv
        described_class.new(history_experiment.candidates.including_relationships.order(:id), project: project).present
      end

      it 'writes the latest value of each metric, with the metric columns sorted by name', :aggregate_failures do
        parsed = CSV.parse(present_csv, headers: true)

        expect(parsed.headers.last(2)).to eq(%w[accuracy loss])
        expect(parsed.map { |row| row.fields.last(2) }).to eq([%w[0.5 2.0], %w[10.5 12.0]])
      end

      it 'does not load the metric history' do
        expect { present_csv }
          .not_to make_queries_matching(/FROM "ml_candidate_metrics" WHERE "ml_candidate_metrics"\."candidate_id" = /)
      end

      it 'writes the same values as when ml_bounded_candidate_metric_reads is disabled' do
        rows_with_flag = CSV.parse(present_csv, headers: true).map(&:to_h)

        stub_feature_flags(ml_bounded_candidate_metric_reads: false)

        expect(CSV.parse(present_csv, headers: true).map(&:to_h)).to eq(rows_with_flag)
      end
    end
  end
end
