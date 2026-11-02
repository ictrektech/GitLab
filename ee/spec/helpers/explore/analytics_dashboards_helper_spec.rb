# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Explore::AnalyticsDashboardsHelper, feature_category: :custom_dashboards_foundation do
  let_it_be(:user) { build_stubbed(:user) }

  before do
    allow(helper).to receive(:current_user) { user }
  end

  describe '#explore_gitlab_credits_dashboard_path' do
    using RSpec::Parameterized::TableSyntax

    subject { helper.explore_gitlab_credits_dashboard_path }

    where(:admin, :saas, :entitled, :expected_path) do
      true  | false | true  | '/admin/gitlab_credits_dashboard'
      false | false | true  | nil
      true  | true  | true  | nil
      true  | false | false | nil
    end

    with_them do
      before do
        allow(user).to receive(:can_admin_all_resources?).and_return(admin)
        stub_saas_features(gitlab_com_subscriptions: saas)
        allow(License).to receive(:gitlab_credits_entitled?).and_return(entitled)
      end

      it { is_expected.to eq(expected_path) }
    end
  end
end
