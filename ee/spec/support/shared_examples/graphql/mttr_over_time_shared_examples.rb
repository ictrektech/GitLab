# frozen_string_literal: true

# Expects `mttr_over_time_data` (the `mttrOverTime` list from the response) and `remediated_week`
# (the Monday of the week holding one critical SAST vulnerability remediated 3 days after detection).
RSpec.shared_examples 'a dense mttrOverTime response' do
  it 'returns every week, with every severity and report type, zero-filled', :aggregate_failures do
    buckets = mttr_over_time_data.index_by { |bucket| bucket['startDate'] }
    remediated = buckets.fetch(remediated_week.to_date.iso8601)
    empty = buckets.fetch((remediated_week + 1.week).to_date.iso8601)

    expect(remediated).to include('count' => 1, 'sumDays' => 3.0, 'mttr' => 3.0)
    expect(remediated['bySeverity']).to include({ 'severity' => 'CRITICAL', 'count' => 1, 'sumDays' => 3.0,
      'mttr' => 3.0 })
    expect(remediated['byReportType']).to include({ 'reportType' => 'SAST', 'count' => 1, 'sumDays' => 3.0,
      'mttr' => 3.0 })

    expect(empty).to include('count' => 0, 'sumDays' => 0.0, 'mttr' => nil)
    expect(empty['bySeverity']).to all(include('count' => 0, 'sumDays' => 0.0, 'mttr' => nil))
    expect(empty['byReportType']).to all(include('count' => 0, 'sumDays' => 0.0, 'mttr' => nil))

    mttr_over_time_data.each do |bucket|
      expect(bucket['bySeverity'].pluck('severity'))
        .to match_array(::Enums::Vulnerability.severity_levels.keys.map { |severity| severity.to_s.upcase })
      expect(bucket['byReportType'].pluck('reportType'))
        .to match_array(::Enums::Vulnerability.report_types.keys.map { |report_type| report_type.to_s.upcase })
    end
  end
end
