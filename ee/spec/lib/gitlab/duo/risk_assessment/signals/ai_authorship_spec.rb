# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskAssessment::Signals::AiAuthorship, feature_category: :dap_code_review do
  let_it_be(:project) { create(:project) }

  let(:merge_request) { build(:merge_request, source_project: project, target_project: project) }
  let(:session_tracking_enabled) { true }
  let(:commits) { [] }

  subject(:signal) { described_class.new(merge_request) }

  before do
    allow(project.project_setting)
      .to receive(:dap_session_tracking_enabled?).and_return(session_tracking_enabled)
    allow(merge_request).to receive(:commits).with(load_from_gitaly: true).and_return(commits)
  end

  def commit(agent_authored:)
    instance_double(Commit, has_agent_session?: agent_authored)
  end

  it_behaves_like 'a signal with dimensions', 'Commit authorship', {
    agent_authored: 'Agent-authored commits'
  }

  describe '#available?' do
    context 'when the project tracks agent sessions' do
      it { is_expected.to be_available }
    end

    context 'when the project does not track agent sessions' do
      let(:session_tracking_enabled) { false }

      it 'is unavailable, because authorship is unknown rather than human' do
        is_expected.not_to be_available
      end
    end

    context 'when the project has no settings record' do
      before do
        project_without_setting = build_stubbed(:project)
        allow(project_without_setting).to receive(:project_setting).and_return(nil)
        allow(merge_request).to receive(:project).and_return(project_without_setting)
      end

      it { is_expected.not_to be_available }
    end
  end

  describe '#extract' do
    context 'when no commit came from an agent' do
      let(:commits) { [commit(agent_authored: false), commit(agent_authored: false)] }

      it { expect(signal.extract).to eq({ agent_authored: 0.0 }) }
    end

    context 'when every commit came from an agent' do
      let(:commits) { [commit(agent_authored: true), commit(agent_authored: true)] }

      it { expect(signal.extract).to eq({ agent_authored: 1.0 }) }
    end

    context 'when some commits came from an agent' do
      let(:commits) do
        [commit(agent_authored: true), commit(agent_authored: false),
          commit(agent_authored: false), commit(agent_authored: false)]
      end

      it { expect(signal.extract).to eq({ agent_authored: 0.25 }) }
    end

    context 'when there are no commits' do
      it 'does not divide by zero' do
        expect(signal.extract).to eq({ agent_authored: 0.0 })
      end
    end

    it 'loads commits once even when extract is called repeatedly' do
      expect(merge_request).to receive(:commits).with(load_from_gitaly: true).once.and_return([])

      signal.extract
      signal.extract
    end
  end
end
