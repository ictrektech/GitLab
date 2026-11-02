# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::DisableBetaEnrollmentsService, feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }

  let(:trial_status) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false) }

  subject(:result) { described_class.new.execute }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_feature_flags(orbit_promo_access_gate: true)
    allow(Analytics::Orbit::Trial).to receive(:request_status_for).and_return(trial_status)
  end

  def enrollment_source(namespace)
    namespace.reload.orbit_namespace_enrollment&.source
  end

  context 'with a beta group that has Orbit on' do
    before do
      create(:orbit_namespace_enrollment, :beta, namespace: group)
      create(:knowledge_graph_enabled_namespace, namespace: group)
    end

    it 'logs the disabled namespace IDs so they can be re-enabled' do
      expect(Gitlab::AppLogger).to receive(:info).with(hash_including(disabled_namespace_ids: [group.id]))

      result
    end

    it 'deletes the enabled namespace and the enrollment' do
      expect(result.payload[:disabled_count]).to eq(1)
      expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
      expect(group.orbit_namespace_enrollment).to be_nil
    end

    context 'when the group has an active orbit_promo add-on' do
      before do
        create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)
      end

      it 'keeps Orbit on and makes the enrollment direct' do
        expect(result.payload).to include(disabled_count: 0, converted_count: 1)
        expect(group.reload.knowledge_graph_enabled_namespace).to be_present
        expect(enrollment_source(group)).to eq('direct')
      end

      it 'does not ask CDot' do
        expect(Analytics::Orbit::Trial).not_to receive(:request_status_for)

        result
      end
    end

    context 'when CDot has an active trial for the group' do
      let(:trial_status) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true) }

      it 'keeps Orbit on with trial access' do
        expect(result.payload).to include(disabled_count: 0, converted_count: 1)
        expect(group.reload.knowledge_graph_enabled_namespace).to be_present
        expect(enrollment_source(group)).to eq('trial')
        expect(Analytics::Orbit::Billing.account_for(group)).to be_entitled
      end
    end

    context 'when CDot cannot answer' do
      let(:trial_status) { :unavailable }

      it 'keeps the beta enrollment for the next run' do
        expect(result.payload).to include(disabled_count: 0, converted_count: 0)
        expect(group.reload.knowledge_graph_enabled_namespace).to be_present
        expect(enrollment_source(group)).to eq('beta')
      end
    end

    context 'when the group is opted out of the gate' do
      before do
        Feature.opt_out(:orbit_promo_access_gate, group)
      end

      it 'keeps Orbit on and makes the enrollment direct' do
        expect(result.payload).to include(disabled_count: 0, converted_count: 1)
        expect(group.reload.knowledge_graph_enabled_namespace).to be_present
        expect(enrollment_source(group)).to eq('direct')
      end
    end
  end

  it 'deletes a beta enrollment of a group that has Orbit off' do
    create(:orbit_namespace_enrollment, :beta, namespace: group)

    expect(result.payload[:disabled_count]).to eq(1)
    expect(group.reload.orbit_namespace_enrollment).to be_nil
  end

  it 'keeps trial and direct enrollments' do
    trial_group = create(:group)
    create(:orbit_namespace_enrollment, namespace: trial_group, source: :trial)
    create(:knowledge_graph_enabled_namespace, namespace: trial_group)
    create(:orbit_namespace_enrollment, namespace: group, source: :direct)
    create(:knowledge_graph_enabled_namespace, namespace: group)

    expect(result.payload[:disabled_count]).to eq(0)
    expect(enrollment_source(trial_group)).to eq('trial')
    expect(enrollment_source(group)).to eq('direct')
    expect(Analytics::KnowledgeGraph::EnabledNamespace.count).to eq(2)
  end

  it 'processes groups in several batches' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    groups = create_list(:group, 2)
    groups.each { |g| create(:orbit_namespace_enrollment, :beta, namespace: g) }

    expect(result.payload).to include(disabled_count: 2, over_time: false)
  end

  it 'stops after the runtime limit and leaves the other beta rows for the next run' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    first_group, second_group = create_list(:group, 2).sort_by(&:id)
    [first_group, second_group].each { |g| create(:orbit_namespace_enrollment, :beta, namespace: g) }
    allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
      allow(limiter).to receive_messages(over_time?: true, was_over_time?: true)
    end

    expect(result.payload).to eq(disabled_count: 1, converted_count: 0, over_time: true)
    expect(first_group.reload.orbit_namespace_enrollment).to be_nil
    expect(enrollment_source(second_group)).to eq('beta')
  end

  it 'keeps an enrollment that turned into a trial after it was selected' do
    create(:orbit_namespace_enrollment, :beta, namespace: group)
    create(:knowledge_graph_enabled_namespace, namespace: group)
    allow(Analytics::Orbit::NamespaceEnrollment).to receive(:convert_beta_to_direct)
      .and_wrap_original do |original, *args|
      Analytics::Orbit::NamespaceEnrollment.convert_beta_to_trial(group.id)
      original.call(*args)
    end

    expect(result.payload[:disabled_count]).to eq(0)
    expect(group.reload.knowledge_graph_enabled_namespace).to be_present
    expect(enrollment_source(group)).to eq('trial')
  end
end
