# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Status::Bridge::Failed, feature_category: :continuous_integration do
  let_it_be(:project, freeze: true) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  let(:user) { build_stubbed(:user) }
  let(:core_status) { Gitlab::Ci::Status::Failed.new(bridge, user) }

  subject(:status) { described_class.new(core_status) }

  describe '#status_tooltip' do
    context 'with a known failure reason' do
      let(:bridge) { create(:ci_bridge, :failed, failure_reason: :script_failure, pipeline: pipeline) }

      it 'names the reason' do
        expect(status.status_tooltip).to eq('Failed - (script failure)')
      end
    end

    context 'when the rules could not be evaluated' do
      let(:bridge) { create(:ci_bridge, :failed, failure_reason: :rules_parse_failure, pipeline: pipeline) }

      before do
        create(:ci_job_message, job: bridge, severity: :error,
          content: 'rules:changes:compare_to is not a valid ref')
      end

      it 'shows the clause error once' do
        expect(status.status_tooltip).to eq(
          'Failed - (rules could not be evaluated, rules:changes:compare_to is not a valid ref)'
        )
      end
    end
  end
end
