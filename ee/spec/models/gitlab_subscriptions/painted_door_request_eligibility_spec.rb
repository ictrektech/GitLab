# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::PaintedDoorRequestEligibility, :saas_gitlab_com_subscriptions,
  feature_category: :acquisition do
  let_it_be(:user) { create(:user) }

  let(:feature) { :duo_panel }
  let(:namespace) { group }

  subject(:eligibility) { described_class.new(user: user, namespace: namespace, feature: feature) }

  describe '.new' do
    it 'raises for an unknown feature' do
      expect { described_class.new(user: user, namespace: nil, feature: :unknown) }.to raise_error(KeyError)
    end
  end

  describe '#root' do
    let_it_be(:group) { create(:group) }

    it 'returns the root ancestor of the namespace' do
      subgroup = create(:group, parent: group)

      expect(described_class.new(user: user, namespace: subgroup, feature: feature).root).to eq(group)
    end

    it 'returns nil when the namespace is nil' do
      expect(described_class.new(user: user, namespace: nil, feature: feature).root).to be_nil
    end
  end

  describe '#eligible?' do
    subject { eligibility.eligible? }

    context 'when every condition is met' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      it { is_expected.to be(true) }
    end

    context 'when the feature flag is disabled' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      before do
        stub_feature_flags(painted_door_request_ctas: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when not on SaaS' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the namespace is nil' do
      let(:namespace) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the namespace is a personal namespace' do
      let(:namespace) { user.namespace }

      it { is_expected.to be(false) }
    end

    context 'when the group is on a paid plan' do
      let_it_be(:group) { create(:group_with_plan, plan: :premium_plan, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the group has an active trial' do
      let_it_be(:group) { create(:group_with_plan, plan: :ultimate_trial_plan, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the group is on the opensource plan' do
      let_it_be(:group) { create(:group_with_plan, plan: :opensource_plan, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the group had a trial that has since ended and is back on the free plan' do
      let_it_be(:group) do
        create(:group_with_plan, plan: :free_plan, trial: true, trial_starts_on: 31.days.ago,
          trial_ends_on: 1.day.ago, developers: user)
      end

      it { is_expected.to be(true) }
    end

    context 'when the user is not a member of a public group' do
      let_it_be(:group) { create(:group_with_plan, :public, plan: :free_plan) }

      it { is_expected.to be(false) }
    end

    context 'when the user is only a member of a subgroup' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }
      let_it_be(:subgroup) { create(:group, parent: group, developers: user) }

      it { is_expected.to be(true) }
    end

    context 'when the user is only a member of a project under the root group' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }
      let_it_be(:project) { create(:project, group: group, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the user is only a member of a project in a subgroup' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:project) { create(:project, group: subgroup, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the user is a member of a different root namespace' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }
      let_it_be(:other_group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      it { is_expected.to be(false) }
    end

    context 'when the user has a pending access request to the root group' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }

      before do
        create(:group_member, :access_request, user: user, group: group)
      end

      it { is_expected.to be(false) }
    end

    context 'when the user membership is in an awaiting state' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan) }

      before do
        create(:group_member, :awaiting, user: user, group: group)
      end

      it { is_expected.to be(false) }
    end

    context 'when the plan and ability caches are warm, as on a sidebar render', :request_store do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }
      let(:feature) { :explore_premium }

      it 'runs only the membership query' do
        group.actual_plan
        Ability.allowed?(user, :edit_billing, group)

        expect { eligibility.eligible? }.not_to exceed_query_limit(1)
      end
    end

    context 'when the user is the group Owner' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, owners: user) }

      it { is_expected.to be(false) }
    end

    context 'when the user is a Maintainer' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, maintainers: user) }

      it { is_expected.to be(true) }
    end

    context 'when the user is a GitLab team member' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      before do
        allow(user).to receive(:gitlab_team_member?).and_return(true)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature checks credits' do
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      context 'and the group has an active gitlab_credits add-on' do
        before do
          create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
        end

        it { is_expected.to be(false) }
      end

      context 'and the group has no gitlab_credits add-on' do
        it { is_expected.to be(true) }
      end
    end

    context 'when the feature does not check credits' do
      let(:feature) { :explore_premium }
      let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
      end

      it { is_expected.to be(true) }
    end
  end

  describe '#requested?' do
    # refind so each example gets a fresh User instance; dismissed_callout_for_group? memoizes
    # group_callouts_by_feature_name on the instance, which would otherwise leak between examples.
    let_it_be_with_refind(:user) { create(:user) }
    let_it_be(:group) { create(:group_with_plan, plan: :free_plan, developers: user) }

    subject { eligibility.requested? }

    context 'when the user has requested the feature' do
      before do
        create(:group_callout, user: user, group: group, feature_name: :duo_panel_request_painted_door)
      end

      it { is_expected.to be(true) }
    end

    context 'when the user has not requested the feature' do
      it { is_expected.to be(false) }
    end
  end
end
