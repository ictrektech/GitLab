# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting Incident Management on-call shifts', feature_category: :incident_management do
  include GraphqlHelpers

  let_it_be(:participant) { create(:incident_management_oncall_participant, :utc, :with_developer_access) }
  let_it_be(:rotation) { participant.rotation }
  let_it_be(:project) { rotation.project }
  let_it_be(:current_user) { participant.user }

  let(:starts_at) { rotation.starts_at }
  let(:ends_at) { rotation.starts_at + rotation.shift_cycle_duration } # intentionally return one shift
  let(:params) { { start_time: starts_at.iso8601, end_time: ends_at.iso8601 } }

  let(:shift_fields) do
    <<~QUERY
      nodes {
        participant { id user { id } }
        endsAt
        startsAt
      }
    QUERY
  end

  let(:schedule_fields) do
    <<~QUERY
      nodes {
        rotations {
          nodes {
            #{query_graphql_field('shifts', params, shift_fields)}
          }
        }
      }
    QUERY
  end

  let(:query) do
    graphql_query_for(
      'project',
      { 'fullPath' => project.full_path },
      query_graphql_field('incidentManagementOncallSchedules', {}, schedule_fields)
    )
  end

  let(:shifts) do
    graphql_data
      .dig('project', 'incidentManagementOncallSchedules', 'nodes').first
      .dig('rotations', 'nodes').first
      .dig('shifts', 'nodes')
  end

  before do
    stub_licensed_features(oncall_schedules: true)
    post_graphql(query, current_user: current_user)
  end

  it_behaves_like 'a working graphql query'

  describe 'the on-call schedule details query' do
    let_it_be(:target_schedule) { create(:incident_management_oncall_schedule, project: project) }
    let_it_be(:target_rotation) do
      create(:incident_management_oncall_rotation, :with_participants, schedule: target_schedule)
    end

    let_it_be(:second_target_rotation) do
      create(:incident_management_oncall_rotation, :with_participants, schedule: target_schedule)
    end

    let_it_be(:hourly_rotation) do
      create(:incident_management_oncall_rotation, :with_participants,
        schedule: target_schedule, starts_at: 1.year.from_now.beginning_of_day, length: 1, length_unit: :hours)
    end

    let(:query_path) do
      'oncall_schedules/graphql/queries/get_oncall_schedules_with_rotations_shifts.query.graphql'
    end

    let(:frontend_query) { get_graphql_query_as_string(query_path, ee: true) }
    let(:frontend_variables) do
      {
        projectPath: project.full_path,
        iid: target_schedule.iid,
        startsAt: starts_at.iso8601,
        endsAt: ends_at.iso8601
      }
    end

    it 'returns the requested schedule and all of its rotations within the complexity budget' do
      post_graphql(frontend_query, current_user: current_user, variables: frontend_variables)

      expect_graphql_errors_to_be_empty
      schedules = graphql_data.dig('project', 'incidentManagementOncallSchedules', 'nodes')
      expect(schedules).to have_attributes(size: 1)
      expect(schedules.first.dig('rotations', 'nodes').pluck('id')).to contain_exactly(
        target_rotation.to_global_id.to_s,
        second_target_rotation.to_global_id.to_s,
        hourly_rotation.to_global_id.to_s
      )
    end

    it 'returns hourly shifts and participants through the existing 350-shift connection' do
      variables = frontend_variables.merge(
        startsAt: hourly_rotation.starts_at.iso8601,
        endsAt: (hourly_rotation.starts_at + 336.hours).iso8601
      )

      post_graphql(frontend_query, current_user: current_user, variables: variables)

      expect_graphql_errors_to_be_empty
      rotations = graphql_data.dig('project', 'incidentManagementOncallSchedules', 'nodes', 0, 'rotations', 'nodes')
      rotation = rotations.find { |item| item['id'] == hourly_rotation.to_global_id.to_s }
      shifts = rotation['shifts']['nodes']

      expect(shifts).to have_attributes(size: 336)
      expect(shifts.first['startsAt']).to eq(hourly_rotation.starts_at.iso8601)
      expect(shifts.last['endsAt']).to eq((hourly_rotation.starts_at + 336.hours).iso8601)
      expect(rotation['participants']['nodes'].pluck('id')).to match_array(hourly_rotation.participants.map { |p| p.to_global_id.to_s })
      expect(shifts.pluck('participant').pluck('id')).to all(be_in(hourly_rotation.participants.map { |p| p.to_global_id.to_s }))
    end

    it 'exceeds the complexity budget without the single-schedule limit' do
      query_without_first = frontend_query.sub('iids: [$iid], first: 1', 'iids: [$iid]')

      expect(query_without_first).not_to eq(frontend_query)

      post_graphql(query_without_first, current_user: current_user, variables: frontend_variables)

      expect(graphql_errors).to include(a_hash_including('message' => a_string_including('exceeds max complexity')))
    end
  end

  it 'returns the correct properties of the on-call shifts' do
    expect(shifts.first).to include(
      'participant' => {
        'id' => participant.to_global_id.to_s,
        'user' => { 'id' => participant.user.to_global_id.to_s }
      },
      'startsAt' => params[:start_time],
      'endsAt' => params[:end_time]
    )
  end

  context 'performance' do
    shared_examples 'avoids N+1 queries' do
      specify do
        base_count = ActiveRecord::QueryRecorder.new do
          post_graphql(query, current_user: current_user)
        end

        action

        expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(base_count)
      end
    end

    shared_examples 'avoids N+1 queries for additional generated shift' do
      include_examples 'avoids N+1 queries' do
        let(:action) { params[:end_time] = ends_at.next_day.iso8601 }
      end
    end

    shared_examples 'avoids N+1 queries for additional historical shift' do
      include_examples 'avoids N+1 queries' do
        let(:action) { create(:incident_management_oncall_shift, participant: participant, starts_at: last_shift.ends_at) }
      end
    end

    shared_examples 'avoids N+1 queries for additional participant' do
      include_examples 'avoids N+1 queries' do
        let(:action) { create(:incident_management_oncall_participant, rotation: rotation) }
      end
    end

    shared_examples 'avoids N+1 queries for additional rotation with participants' do
      include_examples 'avoids N+1 queries' do
        let(:action) { create(:incident_management_oncall_rotation, :with_participants, schedule: rotation.schedule) }
      end
    end

    shared_examples 'adds only one query for each additional rotation with participants' do
      specify do
        base_count = ActiveRecord::QueryRecorder.new do
          post_graphql(query, current_user: current_user)
        end

        create(:incident_management_oncall_rotation, :with_participants, schedule: rotation.schedule)
        create(:incident_management_oncall_rotation, :with_participants, schedule: rotation.schedule)

        expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(base_count).with_threshold(2)
      end
    end

    context 'for past and future shifts' do
      let_it_be(:last_shift) do
        create(:incident_management_oncall_shift,
          participant: participant,
          starts_at: rotation.starts_at - 1.day
        )
      end

      let(:ends_at) { rotation.starts_at + (2 * rotation.shift_cycle_duration) }

      around do |example|
        freeze_time { example.run }
      end

      it_behaves_like 'avoids N+1 queries for additional generated shift'
      it_behaves_like 'avoids N+1 queries for additional historical shift'
      it_behaves_like 'avoids N+1 queries for additional participant'
      it_behaves_like 'adds only one query for each additional rotation with participants'
    end

    context 'for future shifts only' do
      let(:starts_at) { rotation.starts_at + rotation.shift_cycle_duration }
      let(:ends_at) { rotation.starts_at + (2 * rotation.shift_cycle_duration) }

      it_behaves_like 'avoids N+1 queries for additional generated shift'
      it_behaves_like 'avoids N+1 queries for additional participant'
      it_behaves_like 'avoids N+1 queries for additional rotation with participants'
    end

    context 'for past shifts only' do
      let_it_be(:last_shift) { create(:incident_management_oncall_shift, participant: participant) }

      around do |example|
        travel_to(starts_at + (1.5 * rotation.shift_cycle_duration)) { example.run }
      end

      it_behaves_like 'avoids N+1 queries for additional historical shift'
      it_behaves_like 'avoids N+1 queries for additional participant'
      it_behaves_like 'adds only one query for each additional rotation with participants'
    end
  end

  context "without required argument starts_at" do
    let(:params) { { end_time: ends_at.iso8601 } }

    it 'raises an exception' do
      expect(graphql_errors).to include(a_hash_including('message' => "Field 'shifts' is missing required arguments: startTime"))
    end
  end

  context "without required argument ends_at" do
    let(:params) { { start_time: starts_at.iso8601 } }

    it 'raises an exception' do
      expect(graphql_errors).to include(a_hash_including('message' => "Field 'shifts' is missing required arguments: endTime"))
    end
  end
end
