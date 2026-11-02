# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventForward::EventForwardController, feature_category: :product_analytics do
  let(:tracker) { instance_double(Gitlab::Tracking::Destinations::Snowplow) }
  let(:event_eligibility_checker) { instance_double(Gitlab::Tracking::EventEligibilityChecker) }
  let(:logger) { instance_double(Logger) }
  let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1' } }
  let(:event_2) { { 'se_ac' => 'event_2', 'aid' => 'app_id_2' } }
  let(:payload) do
    {
      'data' => [
        event_1,
        event_2
      ]
    }
  end

  before do
    allow(Gitlab::Tracking).to receive(:tracker).and_return(tracker)
    allow(tracker).to receive_messages(emit_event_payload: nil, hostname: 'localhost')
    allow(Gitlab::Tracking::EventEligibilityChecker).to receive(:new).and_return(event_eligibility_checker)
    allow(event_eligibility_checker).to receive(:eligible?).and_return(true)
    allow(EventForward::Logger).to receive(:build).and_return(logger)
    allow(logger).to receive(:info)
  end

  describe 'POST #forward' do
    let(:request) { post event_forwarding_path, params: payload, as: :json }

    context 'when instance type is Dedicated', :dedicated do
      it 'forwards each event to the Snowplow tracker with dedicated app_id suffix' do
        payload['data'].each do |event|
          expected_event = event.merge('aid' => "#{event['aid']}_dedicated")

          expect(tracker).to receive(:emit_event_payload).with(expected_event)
        end

        request
      end

      context 'when filtering events by eligibility' do
        before do
          allow(event_eligibility_checker).to receive(:eligible?).with('event_1', 'app_id_1').and_return(true)
          allow(event_eligibility_checker).to receive(:eligible?).with('event_2', 'app_id_2').and_return(false)
        end

        it 'forwards only eligible events to the Snowplow tracker with dedicated app_id suffix' do
          expected_event = event_1.merge('aid' => 'app_id_1_dedicated')

          expect(tracker).to receive(:emit_event_payload).with(expected_event)
          expect(tracker).not_to receive(:emit_event_payload).with(event_2)

          request
        end
      end
    end
  end
end
