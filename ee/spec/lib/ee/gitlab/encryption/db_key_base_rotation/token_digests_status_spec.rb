# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Encryption::DbKeyBaseRotation::TokenDigestsStatus, feature_category: :system_access do
  let_it_be(:rotated_at) { 1.day.ago }
  let_it_be(:runner_controller) { create(:ci_runner_controller) }

  subject(:status) { described_class.new(rotated_at: rotated_at) }

  def runner_controller_token_result
    status.execute.detect { |result| result.model == 'Ci::RunnerControllerToken' }
  end

  it 'allows retiring today without tokens created before the rotation' do
    expect(runner_controller_token_result).to have_attributes(remaining: 0, without_expiry: 0)
    expect(status.retirement_date).to eq(Date.current)
  end

  it 'has no retirement date while a runner controller token is unused since the rotation' do
    create(:ci_runner_controller_token, runner_controller: runner_controller, created_at: 2.days.ago)

    expect(runner_controller_token_result).to have_attributes(remaining: 1, without_expiry: 1, latest_expiry: nil)
    expect(status.retirement_date).to be_nil
  end

  it 'ignores runner controller tokens used since the rotation' do
    create(:ci_runner_controller_token, runner_controller: runner_controller, created_at: 2.days.ago,
      last_used_at: 1.hour.ago)

    expect(runner_controller_token_result).to have_attributes(remaining: 0)
  end
end
