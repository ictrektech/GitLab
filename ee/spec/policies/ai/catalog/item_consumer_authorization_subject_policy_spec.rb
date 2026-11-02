# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumerAuthorizationSubjectPolicy, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:private_project) { create(:project, :private, group: subgroup) }
  let_it_be(:sibling_project) { create(:project, :private, group: group) }
  let_it_be(:project_outside_group) { create(:project, :private) }

  let_it_be(:guest) { create(:user) }
  let_it_be(:reporter) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:admin) { create(:admin) }

  let_it_be(:item) do
    create(:ai_catalog_flow, :public, :with_released_version, organization: group.organization)
  end

  let_it_be_with_reload(:inheritance_consumer) do
    create(:ai_catalog_item_consumer, :inheritance, group: group, item: item)
  end

  let_it_be(:public_group) { create(:group, :public) }
  let_it_be(:public_project) { create(:project, :public, group: public_group) }

  let_it_be(:public_item) do
    create(:ai_catalog_flow, :public, :with_released_version, organization: public_group.organization)
  end

  let_it_be_with_reload(:public_inheritance_consumer) do
    create(:ai_catalog_item_consumer, :inheritance, group: public_group, item: public_item)
  end

  before_all do
    private_project.add_guest(guest)
    private_project.add_reporter(reporter)
    private_project.add_developer(developer)
    private_project.add_owner(owner)
  end

  subject(:policy) { described_class.new(current_user, scoped_consumer) }

  before do
    enable_ai_catalog
  end

  it 'delegates to the item consumer policy' do
    scoped_consumer = Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, private_project)

    expect(described_class.new(developer, scoped_consumer)).to delegate_to(Ai::Catalog::ItemConsumerPolicy)
  end

  shared_examples 'disallowed when the item consumer is not inherited by the project' do |ability|
    let(:current_user) { developer }

    context 'when the project is outside the group of the item consumer' do
      let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, project_outside_group) }

      before_all do
        project_outside_group.add_developer(developer)
      end

      it { expect_disallowed(ability) }
    end

    context 'when the item consumer is a direct record' do
      let_it_be(:direct_item) do
        create(:ai_catalog_flow, :public, :with_released_version, organization: group.organization)
      end

      let_it_be(:direct_consumer) { create(:ai_catalog_item_consumer, group: group, item: direct_item) }

      let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(direct_consumer, private_project) }

      it { expect_disallowed(ability) }
    end

    context 'when ai_catalog_group_inherited_consumers feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it { expect_disallowed(ability) }
    end

    context 'when a blocking rule on the item consumer applies' do
      before do
        inheritance_consumer.root_ancestor.namespace_settings.update!(duo_custom_flows_enabled: false)
      end

      it { expect_disallowed(ability) }
    end
  end

  describe 'read_ai_catalog_item_consumer' do
    let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, private_project) }

    where(:current_user, :allowed) do
      ref(:non_member) | false
      ref(:guest)      | true
    end

    with_them do
      if params[:allowed]
        it { expect_allowed(:read_ai_catalog_item_consumer) }
      else
        it { expect_disallowed(:read_ai_catalog_item_consumer) }
      end
    end

    context 'with admin mode enabled', :enable_admin_mode do
      let(:current_user) { admin }

      it { expect_allowed(:read_ai_catalog_item_consumer) }
    end

    context 'without admin mode enabled' do
      let(:current_user) { admin }

      it { expect_disallowed(:read_ai_catalog_item_consumer) }
    end

    context 'when the project is public and user is not a member of the project' do
      let(:current_user) { non_member }
      let(:scoped_consumer) do
        Ai::Catalog::ItemConsumerAuthorizationSubject.new(public_inheritance_consumer, public_project)
      end

      it { expect_disallowed(:read_ai_catalog_item_consumer) }
    end

    it_behaves_like 'disallowed when the item consumer is not inherited by the project',
      :read_ai_catalog_item_consumer
  end

  describe 'execute_ai_catalog_item' do
    let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, private_project) }

    where(:current_user, :allowed) do
      ref(:reporter)  | false
      ref(:developer) | true
    end

    with_them do
      if params[:allowed]
        it { expect_allowed(:execute_ai_catalog_item) }
      else
        it { expect_disallowed(:execute_ai_catalog_item) }
      end
    end

    context 'with admin mode enabled', :enable_admin_mode do
      let(:current_user) { admin }

      it { expect_allowed(:execute_ai_catalog_item) }
    end

    context 'without admin mode enabled' do
      let(:current_user) { admin }

      it { expect_disallowed(:execute_ai_catalog_item) }
    end

    context 'when user is a guest of the project and a developer of a sibling project' do
      let_it_be(:guest_developer_in_sibling) { create(:user) }

      let(:current_user) { guest_developer_in_sibling }

      before_all do
        private_project.add_guest(guest_developer_in_sibling)
        sibling_project.add_developer(guest_developer_in_sibling)
      end

      it { expect_disallowed(:execute_ai_catalog_item) }

      context 'when scoped to the sibling project' do
        let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, sibling_project) }

        it { expect_allowed(:execute_ai_catalog_item) }
      end
    end

    context 'when AI Catalog is not available for the group of the item consumer' do
      let(:current_user) { developer }

      before do
        inheritance_consumer.root_ancestor.namespace_settings.update!(duo_features_enabled: false)
      end

      it { expect_disallowed(:execute_ai_catalog_item) }
    end

    context 'when the project is public and user is not a member of the project' do
      let(:current_user) { non_member }
      let(:scoped_consumer) do
        Ai::Catalog::ItemConsumerAuthorizationSubject.new(public_inheritance_consumer, public_project)
      end

      it { expect_disallowed(:execute_ai_catalog_item) }
    end

    it_behaves_like 'disallowed when the item consumer is not inherited by the project', :execute_ai_catalog_item
  end

  describe 'admin_ai_catalog_item_consumer' do
    let(:scoped_consumer) { Ai::Catalog::ItemConsumerAuthorizationSubject.new(inheritance_consumer, private_project) }

    context 'when user is an owner of the project' do
      let(:current_user) { owner }

      it { expect_disallowed(:admin_ai_catalog_item_consumer) }
    end

    context 'with admin mode enabled', :enable_admin_mode do
      let(:current_user) { admin }

      it { expect_allowed(:admin_ai_catalog_item_consumer) }
    end

    context 'without admin mode enabled' do
      let(:current_user) { admin }

      it { expect_disallowed(:admin_ai_catalog_item_consumer) }
    end
  end
end
