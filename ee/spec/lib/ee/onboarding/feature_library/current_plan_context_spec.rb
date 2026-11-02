# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::CurrentPlanContext, feature_category: :onboarding do
  subject(:plan_context) { described_class.new(resource: resource) }

  context 'on GitLab.com', :saas_gitlab_com_subscriptions do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project) { create(:project, group: subgroup) }

    let(:resource) { project }

    def subscribe(*traits, **attributes)
      create(:gitlab_subscription, *traits, namespace: group, **attributes)
    end

    it 'describes a Free namespace' do
      expect(plan_context.to_h).to eq(
        edition: :ee, deployment: :saas, current_plan: :free, base_plan: :free, trial: false
      )
      expect(plan_context.tier_pages).to eq(%i[premium ultimate])
    end

    context 'with a Premium subscription' do
      before do
        subscribe(:premium)
      end

      it 'offers only the Ultimate page' do
        expect(plan_context.to_h).to include(current_plan: :premium, base_plan: :premium, trial: false)
        expect(plan_context.tier_pages).to eq(%i[ultimate])
      end
    end

    context 'with a Silver subscription' do
      before do
        subscribe(:silver)
      end

      it { expect(plan_context.current_plan).to eq(:premium) }
    end

    context 'with a Bronze subscription' do
      before do
        subscribe(:bronze)
      end

      it 'treats the retired Bronze plan as Free' do
        expect(plan_context.current_plan).to eq(:free)
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end

    context 'with an Ultimate subscription' do
      before do
        subscribe(:ultimate)
      end

      it 'offers no pages' do
        expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :ultimate, trial: false)
        expect(plan_context.tier_pages).to eq([])
      end
    end

    context 'with an active Ultimate trial' do
      before do
        subscribe(:active_trial, :ultimate_trial)
      end

      it 'compares against Free' do
        expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :free, trial: true)
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end

    context 'when an Ultimate trial has ended but the plan is not downgraded yet' do
      before do
        subscribe(:active_trial, :ultimate_trial, trial_ends_on: Date.current)
      end

      it 'still compares against Free' do
        expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :free, trial: true)
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end

    context 'with a Premium customer trialing Ultimate' do
      before do
        subscribe(:active_trial, :ultimate_trial_paid_customer)
      end

      it 'compares against Premium' do
        expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :premium, trial: true)
        expect(plan_context.tier_pages).to eq(%i[ultimate])
      end
    end

    context 'when the resource is a group' do
      let(:resource) { subgroup }

      before do
        subscribe(:premium)
      end

      it 'reads the plan from the root namespace' do
        expect(plan_context.current_plan).to eq(:premium)
      end
    end

    context 'without a resource' do
      let(:resource) { nil }

      it { expect(plan_context.current_plan).to eq(:free) }
      it { expect(plan_context.trial?).to be(false) }
      it { expect(plan_context.base_plan).to eq(:free) }
    end
  end

  context 'on self-managed' do
    let(:resource) { build_stubbed(:group) }

    def stub_license(plan:, trial: false, expired: false)
      license = build_stubbed(:license, plan: plan)
      allow(license).to receive_messages(trial?: trial, expired?: expired)
      license
    end

    def stub_current_license(license, billable: license)
      allow(License).to receive_messages(current: license, billable_license: billable)
    end

    context 'without a license' do
      before do
        stub_current_license(nil, billable: nil)
      end

      it 'describes a Free instance' do
        expect(plan_context.to_h).to eq(
          edition: :ee, deployment: :self_managed, current_plan: :free, base_plan: :free, trial: false
        )
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end

    context 'with a Premium license' do
      before do
        stub_current_license(stub_license(plan: License::PREMIUM_PLAN))
      end

      it 'offers only the Ultimate page' do
        expect(plan_context.to_h).to include(current_plan: :premium, base_plan: :premium, trial: false)
        expect(plan_context.tier_pages).to eq(%i[ultimate])
      end
    end

    context 'with a legacy Starter license' do
      before do
        stub_current_license(stub_license(plan: License::STARTER_PLAN))
      end

      it 'treats the retired Starter plan as Free' do
        expect(plan_context.current_plan).to eq(:free)
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end

    context 'with an Ultimate license' do
      before do
        stub_current_license(stub_license(plan: License::ULTIMATE_PLAN))
      end

      it 'offers no pages' do
        expect(plan_context.current_plan).to eq(:ultimate)
        expect(plan_context.tier_pages).to eq([])
      end
    end

    context 'with an Ultimate trial license' do
      let(:trial_license) { stub_license(plan: License::ULTIMATE_PLAN, trial: true) }

      context 'without a paid license underneath' do
        before do
          stub_current_license(trial_license, billable: nil)
        end

        it 'compares against Free' do
          expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :free, trial: true)
          expect(plan_context.tier_pages).to eq(%i[premium ultimate])
        end
      end

      context 'when the billable license is the trial itself' do
        before do
          stub_current_license(trial_license)
        end

        it { expect(plan_context.base_plan).to eq(:free) }
      end

      context 'with a Premium license underneath' do
        before do
          stub_current_license(trial_license, billable: stub_license(plan: License::PREMIUM_PLAN))
        end

        it 'compares against Premium' do
          expect(plan_context.to_h).to include(current_plan: :ultimate, base_plan: :premium, trial: true)
          expect(plan_context.tier_pages).to eq(%i[ultimate])
        end
      end

      context 'with a Starter license underneath' do
        before do
          stub_current_license(trial_license, billable: stub_license(plan: License::STARTER_PLAN))
        end

        it { expect(plan_context.base_plan).to eq(:free) }
      end
    end

    context 'with an expired paid license' do
      before do
        stub_current_license(stub_license(plan: License::PREMIUM_PLAN, expired: true))
      end

      it 'keeps the plan the license still unlocks' do
        expect(plan_context.to_h).to include(current_plan: :premium, base_plan: :premium, trial: false)
        expect(plan_context.tier_pages).to eq(%i[ultimate])
      end
    end

    context 'with an expired trial license' do
      before do
        stub_current_license(stub_license(plan: License::ULTIMATE_PLAN, trial: true, expired: true), billable: nil)
      end

      it 'treats the instance as Free' do
        expect(plan_context.to_h).to include(current_plan: :free, base_plan: :free, trial: false)
        expect(plan_context.tier_pages).to eq(%i[premium ultimate])
      end
    end
  end
end
