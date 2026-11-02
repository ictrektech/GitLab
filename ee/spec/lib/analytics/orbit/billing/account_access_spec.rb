# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::Account, '#access', feature_category: :knowledge_graph do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { build_stubbed(:group) }
  let_it_be(:current_user) { build_stubbed(:user) }

  let(:account) do
    saas ? ::Analytics::Orbit::Billing::GroupAccount.new(group) : ::Analytics::Orbit::Billing::InstanceAccount.new
  end

  subject(:access) { account.access(group: group, current_user: current_user) }

  def cdot(state, expires_at: nil, credits_remaining: nil)
    ::Gitlab::SubscriptionPortal::ProductTrialResponse.new(
      state: state, trial_expires_at: expires_at, credits_remaining: credits_remaining
    )
  end

  def enrollment(kind)
    return if kind == :none

    attrs = {
      beta: { beta?: true, trial?: false, trial_ended_at: nil },
      trial_active: { beta?: false, trial?: true, trial_ended_at: nil },
      trial_ended: { beta?: false, trial?: true, trial_ended_at: Time.current }
    }.fetch(kind)

    instance_double(::Analytics::Orbit::NamespaceEnrollment, **attrs)
  end

  describe 'state and reason' do
    # rubocop:disable Layout/LineLength -- an aligned parameterized table reads best on one line per case
    where(:scenario, :configured, :can_toggle, :can_start, :trial_flow, :entitled, :promo_gate, :promo_add_on,
      :beta_kind, :saas, :enabled, :cdot_status, :expected_state, :expected_reason) do
      'service off'                     | false | false | true  | false | false | false | false | :none         | true  | false | :none              | :not_configured           | nil
      'self-managed, no license'        | true  | false | true  | false | false | false | false | :none         | false | false | :none              | :unlicensed               | :no_license
      'free plan'                       | true  | false | true  | false | false | false | false | :none         | true  | false | :none              | :unlicensed               | :free_plan
      'promo gate, no access, off'      | true  | false | true  | false | false | true  | false | :none         | true  | false | :none              | :unlicensed               | :no_access
      'promo gate, no access, on'       | true  | true  | true  | false | false | true  | false | :none         | true  | true  | :none              | :unlicensed               | :no_access
      'licensed by plan'                | true  | true  | true  | false | true  | false | false | :none         | true  | false | :none              | :licensed                 | :plan
      'licensed by promo add-on'        | true  | true  | true  | false | true  | true  | true  | :none         | true  | true  | :none              | :licensed                 | :promo_add_on
      'licensed by beta'                | true  | true  | true  | false | true  | false | false | :beta         | true  | true  | :none              | :licensed                 | :beta
      'trial eligible'                  | true  | true  | true  | true  | true  | false | false | :none         | true  | false | :cdot_eligible     | :trial_eligible           | nil
      'trial active'                    | true  | true  | true  | true  | true  | false | false | :none         | true  | true  | :cdot_active       | :trial_active             | nil
      'promo gate, active trial, no row' | true | true  | true  | true  | false | true  | false | :none         | true  | true  | :cdot_active       | :trial_active             | nil
      'trial expired by date'           | true  | true  | true  | true  | true  | false | false | :none         | true  | false | :cdot_expired      | :trial_ended              | :trial_expired
      'trial out of credits'            | true  | true  | true  | true  | true  | false | false | :none         | true  | false | :cdot_credits_gone | :trial_ended              | :credits_exhausted
      'trial ended with no end date'    | true  | true  | true  | true  | true  | false | false | :none         | true  | false | :cdot_ended_no_date | :trial_ended | :credits_exhausted
      'trial not eligible'              | true  | true  | true  | true  | true  | false | false | :none         | true  | false | :cdot_ineligible   | :trial_not_eligible       | nil
      'cdot error, orbit on'            | true  | true  | true  | true  | true  | false | false | :none         | true  | true  | :unavailable       | :trial_status_unavailable | nil
      'beta in the trial flow'          | true  | true  | false | true  | true  | false | false | :beta         | true  | true  | :cdot_eligible     | :licensed                 | :beta
      'beta, CustomersDot down'         | true  | true  | false | true  | true  | false | false | :beta         | true  | true  | :unavailable       | :licensed                 | :beta
      'not eligible, cannot start'      | true  | true  | false | true  | true  | false | false | :none         | true  | false | :cdot_ineligible   | :licensed                 | :plan
      'promo gate, eligible while on'   | true  | true  | true  | true  | false | true  | false | :beta         | true  | true  | :cdot_eligible     | :trial_eligible           | nil
      'promo gate, beta, cannot start'  | true  | true  | false | true  | true  | true  | false | :beta         | true  | true  | :cdot_eligible     | :licensed                 | :beta
    end
    # rubocop:enable Layout/LineLength

    with_them do
      let(:trial_status) do
        case cdot_status
        when :cdot_eligible then cdot(:trial_eligible)
        when :cdot_active then cdot(:trial, credits_remaining: 100.0)
        when :cdot_expired then cdot(:expired, expires_at: 1.day.ago)
        when :cdot_credits_gone then cdot(:trial, expires_at: 5.days.from_now, credits_remaining: 0.0)
        when :cdot_ended_no_date then cdot(:expired)
        when :cdot_ineligible then cdot(:ineligible)
        when :none then nil
        else cdot_status
        end
      end

      before do
        allow(::Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(configured)
        allow(account).to receive_messages(
          promo_gate?: promo_gate, promo_add_on?: promo_gate && promo_add_on, entitled?: entitled,
          trial_flow?: trial_flow, trial_status: trial_status
        )
        allow(group).to receive_messages(
          orbit_namespace_enrollment: enrollment(beta_kind),
          knowledge_graph_enabled_namespace:
            (enabled ? instance_double(::Analytics::KnowledgeGraph::EnabledNamespace) : nil)
        )
        allow(::Ability).to receive(:allowed?).and_call_original
        allow(::Ability).to receive(:allowed?)
          .with(current_user, :update_knowledge_graph_setting, group).and_return(can_toggle)
        allow(::Ability).to receive(:allowed?)
          .with(current_user, :read_orbit_trial, group).and_return(trial_flow)
        allow(::Ability).to receive(:allowed?)
          .with(current_user, :start_orbit_trial, group).and_return(can_start)
      end

      it 'computes the expected state and reason' do
        expect(access).to have_attributes(state: expected_state, reason: expected_reason)
      end
    end
  end

  describe 'turn_on_denial_reason' do
    let(:saas) { true }
    let(:trial_status) { cdot(:trial_eligible) }
    let(:entitled) { true }
    let(:promo_add_on) { false }
    let(:promo_gate) { false }
    let(:trial_flow) { true }

    before do
      allow(::Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(true)
      allow(account).to receive_messages(promo_gate?: promo_gate, promo_add_on?: promo_add_on,
        entitled?: entitled, eligible?: true, trial_flow?: trial_flow, trial_status: trial_status)
      allow(group).to receive_messages(orbit_namespace_enrollment: nil, knowledge_graph_enabled_namespace: nil)
      allow(::Ability).to receive(:allowed?).and_call_original
      allow(::Ability).to receive(:allowed?).with(current_user, :read_orbit_trial, group).and_return(trial_flow)
      allow(::Ability).to receive(:allowed?).with(current_user, :start_orbit_trial, group).and_return(true)
      allow(::Ability).to receive(:allowed?)
        .with(current_user, :update_knowledge_graph_setting, group).and_return(can_toggle)
    end

    context 'when the user cannot toggle the setting' do
      let(:can_toggle) { false }

      it { expect(access.turn_on_denial_reason).to eq(:forbidden) }
    end

    context 'when the user can toggle and a trial is required' do
      let(:can_toggle) { true }

      it { expect(access.turn_on_denial_reason).to eq(:trial_required) }
    end

    context 'when the user can toggle and the trial has ended' do
      let(:can_toggle) { true }
      let(:trial_status) { cdot(:expired, expires_at: 1.day.ago) }

      it { expect(access.turn_on_denial_reason).to eq(:trial_ended) }
    end

    context 'when the user can toggle and CustomersDot rejects the group for a trial' do
      let(:can_toggle) { true }
      let(:trial_status) { cdot(:ineligible) }

      it { expect(access.turn_on_denial_reason).to eq(:purchase_required) }
    end

    context 'when turning on is allowed' do
      let(:can_toggle) { true }
      let(:trial_status) { cdot(:trial, credits_remaining: 100.0) }

      it { expect(access.turn_on_denial_reason).to be_nil }
    end

    context 'when CustomersDot is unavailable' do
      let(:can_toggle) { true }
      let(:trial_status) { :unavailable }

      it { expect(access.turn_on_denial_reason).to eq(:unavailable) }

      context 'for a beta group' do
        before do
          allow(group).to receive(:orbit_namespace_enrollment).and_return(enrollment(:beta))
        end

        it 'turns on during the beta without CustomersDot' do
          expect(access.turn_on_denial_reason).to be_nil
        end

        context 'with the promo gate' do
          let(:promo_gate) { true }

          it 'waits for CustomersDot, because the group needs an active trial' do
            expect(access.turn_on_denial_reason).to eq(:unavailable)
          end
        end
      end

      context 'on an instance' do
        let(:saas) { false }

        it 'turns on without CustomersDot, because instance indexing never stops for billing' do
          expect(access.turn_on_denial_reason).to be_nil
        end
      end
    end

    context 'when the promo gate needs a trial and the group is not in the trial flow' do
      let(:can_toggle) { true }
      let(:promo_gate) { true }
      let(:trial_flow) { false }
      let(:trial_status) { nil }

      it { expect(access.turn_on_denial_reason).to eq(:purchase_required) }
    end

    context 'when the user can toggle but cannot read the trial' do
      let(:can_toggle) { true }
      let(:trial_status) { nil }

      before do
        allow(::Ability).to receive(:allowed?).with(current_user, :read_orbit_trial, group).and_return(false)
      end

      where(promo_gate: [true, false])

      with_them do
        it 'requires a trial without reading CustomersDot' do
          expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

          expect(access.turn_on_denial_reason).to eq(:trial_required)
        end
      end
    end

    context 'when Orbit is already on' do
      let(:can_toggle) { true }

      before do
        allow(group).to receive(:knowledge_graph_enabled_namespace)
          .and_return(instance_double(::Analytics::KnowledgeGraph::EnabledNamespace))
      end

      it { expect(access.turn_on_denial_reason).to be_nil }
    end

    context 'on an instance under the promo gate before the trial starts' do
      let(:saas) { false }
      let(:can_toggle) { true }
      let(:promo_gate) { true }

      it { expect(access.turn_on_denial_reason).to be_nil }
    end

    context 'on an instance under the promo gate when the trial status is not known' do
      let(:saas) { false }
      let(:can_toggle) { true }
      let(:promo_gate) { true }
      let(:trial_status) { nil }

      it { expect(access.turn_on_denial_reason).to be_nil }
    end
  end

  describe 'the access of the whole instance' do
    let(:account) { ::Analytics::Orbit::Billing::InstanceAccount.new }

    subject(:instance_access) { account.access(group: nil, current_user: current_user) }

    before do
      allow(::Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(true)
      allow(account).to receive_messages(promo_gate?: promo_gate, promo_add_on?: false, entitled?: true,
        eligible?: true, trial_flow?: trial_flow, trial_status: trial_status)
    end

    where(:scenario, :promo_gate, :trial_flow, :cdot_status, :expected_state, :expected_reason) do
      'beta, no trial flow'          | false | false | :none          | :licensed                 | :plan
      'beta, trial not started'      | false | true  | :cdot_eligible | :licensed                 | :plan
      'beta, CustomersDot down'      | false | true  | :unavailable   | :licensed                 | :plan
      'beta, trial active'           | false | true  | :cdot_active   | :trial_active             | nil
      'beta, trial ended'            | false | true  | :cdot_expired  | :trial_ended              | :trial_expired
      'promo gate, trial to start'   | true  | true  | :cdot_eligible | :trial_eligible           | nil
      'promo gate, CustomersDot down' | true | true  | :unavailable   | :trial_status_unavailable | nil
    end

    with_them do
      let(:trial_status) do
        case cdot_status
        when :cdot_eligible then cdot(:trial_eligible)
        when :cdot_active then cdot(:trial, credits_remaining: 100.0)
        when :cdot_expired then cdot(:expired, expires_at: 1.day.ago)
        when :none then nil
        else cdot_status
        end
      end

      it 'computes the expected state and reason' do
        expect(instance_access).to have_attributes(state: expected_state, reason: expected_reason)
      end
    end
  end
end
