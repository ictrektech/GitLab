# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::NamespaceEnrollment, feature_category: :knowledge_graph do
  let_it_be(:group) { create(:group) }

  it { is_expected.to belong_to(:namespace).required.inverse_of(:orbit_namespace_enrollment) }
  it { is_expected.to define_enum_for(:source).with_values(direct: 0, beta: 1, trial: 2) }

  describe 'validations' do
    it 'accepts a top-level group' do
      expect(build(:orbit_namespace_enrollment, namespace: group)).to be_valid
    end

    it 'rejects a subgroup' do
      expect(build(:orbit_namespace_enrollment, namespace: create(:group, parent: group))).to be_invalid
    end

    it 'rejects a user namespace' do
      expect(build(:orbit_namespace_enrollment, namespace: create(:user_namespace))).to be_invalid
    end
  end

  it 'allows one enrollment for each top-level group' do
    create(:orbit_namespace_enrollment, :beta, namespace: group)

    expect { create(:orbit_namespace_enrollment, namespace: group) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'stays when Orbit is turned off for the group' do
    enrollment = create(:orbit_namespace_enrollment, namespace: group)
    create(:knowledge_graph_enabled_namespace, namespace: group).destroy!

    expect(group.reload.orbit_namespace_enrollment).to eq(enrollment)
  end

  describe '.trials_not_ended_for' do
    let_it_be(:enabled_trial) { create(:orbit_namespace_enrollment) }
    let_it_be(:disabled_trial) { create(:orbit_namespace_enrollment) }
    let_it_be(:ended_trial) { create(:orbit_namespace_enrollment, trial_ended_at: 1.day.ago) }
    let_it_be(:enabled_beta) { create(:orbit_namespace_enrollment, :beta) }

    before_all do
      [enabled_trial, ended_trial, enabled_beta].each do |enrollment|
        create(:knowledge_graph_enabled_namespace, namespace: enrollment.namespace)
      end
    end

    it 'returns only trials not ended of groups with Orbit on' do
      enabled_namespaces = ::Analytics::KnowledgeGraph::EnabledNamespace.all

      expect(described_class.trials_not_ended_for(enabled_namespaces)).to contain_exactly(enabled_trial)
    end
  end

  describe '.record_beta' do
    it 'records a beta enrollment' do
      described_class.record_beta(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_beta
    end

    it 'skips subgroups and user namespaces' do
      subgroup = create(:group, parent: group)
      user_namespace = create(:user_namespace)

      described_class.record_beta([subgroup.id, user_namespace.id])

      expect(described_class.count).to eq(0)
    end

    it 'keeps a trial enrollment' do
      create(:orbit_namespace_enrollment, namespace: group)

      described_class.record_beta(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end
  end

  describe '.record_trial' do
    it 'records a trial enrollment' do
      described_class.record_trial(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end

    it 'skips subgroups and user namespaces' do
      subgroup = create(:group, parent: group)
      user_namespace = create(:user_namespace)

      described_class.record_trial([subgroup.id, user_namespace.id])

      expect(described_class.count).to eq(0)
    end

    it 'keeps a beta enrollment' do
      create(:orbit_namespace_enrollment, :beta, namespace: group)

      described_class.record_trial(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_beta
    end
  end

  describe '.record_direct' do
    it 'records a direct enrollment' do
      described_class.record_direct(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_direct
    end

    it 'turns a beta enrollment into a direct enrollment' do
      create(:orbit_namespace_enrollment, :beta, namespace: group)

      described_class.record_direct(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_direct
    end

    it 'keeps a trial enrollment' do
      create(:orbit_namespace_enrollment, namespace: group, source: :trial)

      described_class.record_direct(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end
  end

  describe '.convert_beta_to_trial' do
    it 'turns a beta enrollment into a trial enrollment' do
      create(:orbit_namespace_enrollment, :beta, namespace: group)

      described_class.convert_beta_to_trial(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end

    it 'keeps an enrollment that is not beta' do
      create(:orbit_namespace_enrollment, namespace: group, source: :direct)

      described_class.convert_beta_to_trial(group.id)

      expect(group.reload.orbit_namespace_enrollment).to be_direct
    end
  end
end
