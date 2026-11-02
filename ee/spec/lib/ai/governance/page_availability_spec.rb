# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::PageAvailability, feature_category: :ai_abstraction_layer do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group, freeze: false) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:personal_project) { create(:project, :in_user_namespace) }
  let_it_be(:user_namespace) { personal_project.namespace }

  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:security_manager) { create(:user) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }

  let(:all_tabs) { described_class::TABS }

  subject(:availability) { described_class.new(container, user, organization: organization) }

  before_all do
    group.add_security_manager(security_manager)
    group.namespace_settings.update!(duo_features_enabled: true)
  end

  before do
    stub_licensed_features(
      ai_features: true,
      group_level_compliance_dashboard: true,
      project_level_compliance_dashboard: true
    )
  end

  describe '#available?' do
    let(:user) { owner }

    context 'when the ai_governance_per_tab_permissions flag is enabled' do
      using RSpec::Parameterized::TableSyntax

      where(:container_name, :expected) do
        :group            | true
        :subgroup         | false
        :project          | true
        :personal_project | false
        :user_namespace   | false
      end

      with_them do
        let(:container) { public_send(container_name) }

        it { expect(availability.available?).to be(expected) }
      end

      it 'does not depend on the user abilities or AI licensing', :aggregate_failures do
        stub_licensed_features(ai_features: false)

        expect(described_class.new(group, guest).available?).to be(true)
        expect(described_class.new(project, guest).available?).to be(true)
      end
    end

    context 'when the ai_governance_per_tab_permissions flag is disabled' do
      before do
        stub_feature_flags(ai_governance_per_tab_permissions: false)
      end

      context 'with a root group' do
        let(:container) { group }

        it { expect(availability.available?).to be(true) }

        it 'is false when AI features are not licensed' do
          stub_licensed_features(ai_features: false)

          expect(availability.available?).to be(false)
        end

        it 'is false when the user cannot read tool rules' do
          expect(described_class.new(group, security_manager).available?).to be(false)
        end
      end

      context 'with a subgroup' do
        let(:container) { subgroup }

        it { expect(availability.available?).to be(false) }
      end

      context 'with a group project' do
        let(:container) { project }

        it { expect(availability.available?).to be(true) }

        it 'is false when the user cannot read tool rules on the root group' do
          expect(described_class.new(project, maintainer).available?).to be(false)
        end
      end

      context 'with a personal-namespace project' do
        let(:container) { personal_project }
        let(:user) { personal_project.first_owner }

        it { expect(availability.available?).to be(false) }
      end
    end
  end

  describe '#permitted_tabs' do
    context 'when the ai_governance_per_tab_permissions flag is enabled' do
      using RSpec::Parameterized::TableSyntax

      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(anything, :read_ai_catalog_mcp_server, organization).and_return(false)
      end

      where(:container_name, :user_name, :expected) do
        :group   | :owner            | %w[dashboard tool-management agent-artifacts]
        :group   | :security_manager | %w[dashboard agent-artifacts]
        :group   | :maintainer       | []
        :group   | :guest            | []
        :project | :owner            | %w[dashboard tool-management agent-artifacts]
        :project | :security_manager | %w[dashboard agent-artifacts]
        :project | :maintainer       | []
        :project | :guest            | []
      end

      with_them do
        let(:container) { public_send(container_name) }
        let(:user) { public_send(user_name) }

        it { expect(availability.permitted_tabs).to eq(expected) }
      end

      context 'when a tab has no permission rule' do
        let(:container) { group }
        let(:user) { owner }

        before do
          stub_const("#{described_class}::TABS", [*described_class::TABS, 'unknown-tab'])
        end

        it 'does not permit it' do
          expect(availability.permitted_tabs).not_to include('unknown-tab')
        end
      end

      context 'when the user can read MCP servers in the organization' do
        before do
          allow(Ability).to receive(:allowed?)
            .with(anything, :read_ai_catalog_mcp_server, organization).and_return(true)
        end

        where(:container_name, :user_name, :expected) do
          :group   | :owner            | true
          :group   | :security_manager | false
          :group   | :maintainer       | false
          :group   | :guest            | false
          :project | :owner            | true
          :project | :guest            | false
        end

        with_them do
          let(:container) { public_send(container_name) }
          let(:user) { public_send(user_name) }

          it 'permits the MCP registry tab only to users who can block MCP servers' do
            expect(availability.permitted_tabs.include?('mcp-registry')).to be(expected)
          end
        end
      end

      context 'when no organization is given' do
        subject(:availability) { described_class.new(group, owner) }

        it 'does not permit the MCP registry tab' do
          expect(availability.permitted_tabs).not_to include('mcp-registry')
        end
      end

      context 'when the page is not available' do
        let(:container) { subgroup }
        let(:user) { owner }

        it { expect(availability.permitted_tabs).to be_empty }
      end
    end

    context 'when the ai_governance_per_tab_permissions flag is disabled' do
      let(:container) { group }
      let(:user) { owner }

      before do
        stub_feature_flags(ai_governance_per_tab_permissions: false)
      end

      it 'permits every tab' do
        expect(availability.permitted_tabs).to eq(all_tabs)
      end
    end
  end
end
