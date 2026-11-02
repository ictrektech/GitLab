# frozen_string_literal: true

require 'spec_helper'

# noinspection RubyArgCount -- Rubymine detecting wrong types, it thinks some #create are from Minitest, not FactoryBot
RSpec.describe RemoteDevelopment::GroupPolicy, feature_category: :workspaces do
  include AdminModeHelper
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:admin_in_non_admin_mode) { create(:admin) }
  let_it_be(:admin_in_admin_mode) { create(:admin) }
  let_it_be(:owner) { create(:user, owner_of: [group]) }

  subject(:policy_instance) { GroupPolicy.new(admin_in_non_admin_mode, group) }

  describe ':admin_namespace_cluster_agent_mapping' do
    let(:ability) { :admin_namespace_cluster_agent_mapping }

    where(:policy_class, :user, :result) do
      GroupPolicy | ref(:owner)                   | true
      GroupPolicy | ref(:admin_in_admin_mode)     | true
    end

    with_them do
      subject(:policy_instance) { policy_class.new(user, group) }

      before do
        enable_admin_mode!(admin_in_admin_mode) if user == admin_in_admin_mode
      end

      it { expect(policy_instance.allowed?(ability)).to eq(result) }
    end
  end

  it 'disallows cluster agent mapping abilities for an admin without admin mode' do
    expect_disallowed(:admin_namespace_cluster_agent_mapping, :read_namespace_cluster_agent_mapping)
  end
end
