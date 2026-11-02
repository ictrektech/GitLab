# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dast::ProfilePolicy, feature_category: :dynamic_application_security_testing do
  let_it_be_with_reload(:project) { create(:project, :small_repo) }
  let_it_be(:record) { create(:dast_profile, project: project) }
  let_it_be(:user) { create(:user) }

  subject { described_class.new(user, record) }

  describe 'delegation' do
    it { is_expected.to delegate_to(::ProjectPolicy) }
  end

  it_behaves_like 'a dast on-demand scan policy' do
    let_it_be(:record) { create(:dast_profile, project: project) }
  end

  describe 'update_on_demand_dast_scan' do
    using RSpec::Parameterized::TableSyntax

    before do
      stub_licensed_features(security_on_demand_scans: true)
      project.public_send(:"add_#{role}", user) if role
    end

    context 'when security_on_demand_scans feature is not available' do
      let(:role) { :owner }

      before do
        stub_licensed_features(security_on_demand_scans: false)
      end

      it { expect_disallowed(:update_on_demand_dast_scan) }
    end

    context 'when a user does not have access to the project' do
      let(:role) { nil }

      it { expect_disallowed(:update_on_demand_dast_scan) }
    end

    where(:role, :allowed) do
      :guest            | false
      :reporter         | false
      :developer        | true
      :security_manager | true
    end

    with_them do
      it { allowed ? expect_allowed(:update_on_demand_dast_scan) : expect_disallowed(:update_on_demand_dast_scan) }
    end

    context 'when the user cannot push to the branch' do
      let_it_be(:protected_branch) do
        create(:protected_branch, project: project, name: 'master', authorize_user_to_push: nil,
          authorize_user_to_merge: nil)
      end

      let_it_be(:record) { create(:dast_profile, project: project, branch_name: 'master') }

      where(:role, :allowed) do
        :developer        | false
        :security_manager | true
      end

      with_them do
        it { allowed ? expect_allowed(:update_on_demand_dast_scan) : expect_disallowed(:update_on_demand_dast_scan) }
      end
    end
  end
end
