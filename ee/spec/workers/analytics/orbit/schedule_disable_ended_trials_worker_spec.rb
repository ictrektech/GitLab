# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::ScheduleDisableEndedTrialsWorker, feature_category: :knowledge_graph do
  let(:worker) { described_class.new }
  let(:scheduled_ranges) { ::Analytics::Orbit::DisableEndedTrialsWorker.jobs.pluck('args') }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_const("#{described_class}::BATCH_SIZE", 2)
  end

  it_behaves_like 'an idempotent worker'

  context 'with groups that have Orbit on' do
    let_it_be(:groups) { create_list(:group, 3) }

    before_all do
      groups.each { |group| create(:knowledge_graph_enabled_namespace, namespace: group) }
    end

    it 'schedules one job for each batch of groups' do
      worker.perform

      expect(scheduled_ranges).to eq([[groups[0].id, groups[1].id], [groups[2].id, groups[2].id]])
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'schedules no job and keeps indexing, because the instance trial end turns no group off' do
        expect { worker.perform }
          .not_to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }

        expect(scheduled_ranges).to be_empty
      end
    end
  end

  context 'when no group has Orbit on' do
    it 'schedules no job' do
      worker.perform

      expect(scheduled_ranges).to be_empty
    end
  end
end
