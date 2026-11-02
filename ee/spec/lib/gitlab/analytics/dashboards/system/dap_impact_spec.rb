# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DAP Impact system dashboard', feature_category: :duo_agent_platform do
  let(:config) { Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('dap_impact').config }
  let(:work_view) { config['views'].find { |view| view['title'] == 'Work' } }

  let(:expected_groups) do
    Ai::DuoWorkflows::Workflow::GROUPED_STATUSES.values.map { |statuses| statuses.map(&:to_s) }
  end

  let(:developer_panels) do
    work_view['panels'].select { |panel| glql_for(panel)&.include?('flowType = "developer/v1"') }
  end

  def tooltip_for(panel)
    panel.dig('tooltip', 'description')
  end

  def glql_for(panel)
    panel.dig('visualization', 'data', 'query', 'glql')
  end

  # `status = "x"` or `status in ("x", "y")` in a query, or `status="x"` / `status=["x", "y"]`
  # as a totalCount parameter.
  def statuses_in(text)
    text.scan(/status\s*=?\s*(?:in\s*)?[(\[]?\s*((?:"\w+"(?:\s*,\s*)?)+)[)\]]?/).flatten
      .flat_map { |list| list.scan(/"(\w+)"/).flatten }
  end

  it 'tells readers that credits trail the session counts on every credits panel with a tooltip' do
    credits_panels = config['views'].flat_map { |view| view['panels'] }.select do |panel|
      tooltip_for(panel)&.match?(/credits/i)
    end

    expect(credits_panels.map { |panel| panel['title'] }).to match_array(
      ['Credits consumed', 'Where credits went', 'Group and project comparison', 'Credits by model, by capability',
        'Credits', 'Chat', 'Credits over time']
    )
    expect(credits_panels.map { |panel| tooltip_for(panel) }).to all(
      end_with('so recent totals can understate spend.')
    )
  end

  it 'filters every Developer panel on the Developer flow', :aggregate_failures do
    expect(developer_panels.size).to eq(8)
    expect(work_view['panels'].filter_map { |panel| glql_for(panel) }).to all(exclude('software_development'))
  end

  describe 'the Developer status tiles' do
    let(:tiles) do
      developer_panels.select do |panel|
        glql_for(panel).include?('display: stat') && glql_for(panel).match?(/\bstatus\b/)
      end
    end

    let(:tile_statuses) { tiles.to_h { |panel| [panel['title'], statuses_in(glql_for(panel))] } }

    it 'group the workflow statuses the same way the sessions list does' do
      expect(tile_statuses.values).to match_array(expected_groups)
    end
  end

  it 'plots one over-time series per status group' do
    over_time = developer_panels.find { |panel| glql_for(panel).include?('display: lineChart') }
    series = glql_for(over_time).scan(/totalCount\(([^)]*)\)/).flatten.map { |params| statuses_in(params) }
    expect(series).to match_array(expected_groups)
  end

  it 'counts the same statuses as completed on the Overview tile' do
    overview = config['views'].find { |view| view['title'] == 'Overview' }
    tile = overview['panels'].find { |panel| panel['title'] == 'Completed sessions' }

    expect(statuses_in(glql_for(tile))).to eq(Ai::DuoWorkflows::Workflow::GROUPED_STATUSES[:completed].map(&:to_s))
  end
end
