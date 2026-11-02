# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GroupChildEntity, feature_category: :groups_and_projects do
  include ExternalAuthorizationServiceHelpers
  include Gitlab::Routing.url_helpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :with_sox_compliance_framework) }
  let_it_be(:project_without_compliance_framework) { create(:project) }
  let_it_be(:group) { create(:group) }

  let(:request) { double('request') }
  let(:entity) { described_class.new(object, request: request) }

  subject(:json) { entity.as_json }

  before do
    allow(request).to receive(:current_user).and_return(user)
    stub_commonmark_sourcepos_disabled
  end

  describe 'with compliance framework' do
    shared_examples 'does not have the compliance framework' do
      it do
        expect(json[:compliance_management_frameworks]).to be_nil
      end
    end

    context 'disabled' do
      before do
        stub_licensed_features(compliance_framework: false)
      end

      context 'for a project' do
        let(:object) { project }

        it_behaves_like 'does not have the compliance framework'
      end

      context 'for a group' do
        let(:object) { group }

        it_behaves_like 'does not have the compliance framework'
      end
    end

    describe 'enabled' do
      before do
        stub_licensed_features(compliance_framework: true)
      end

      context 'for a project' do
        let(:object) { project }

        it 'has the compliance framework' do
          expect(json[:compliance_management_frameworks][0]['name']).to eq('SOX')
        end
      end

      context 'for a project without a compliance framework' do
        let(:object) { project_without_compliance_framework }

        it 'returns empty array' do
          expect(json[:compliance_management_frameworks]).to eq([])
        end
      end

      context 'for a group' do
        let(:object) { group }

        it_behaves_like 'does not have the compliance framework'
      end
    end
  end

  describe 'permission fields for a project with a custom role' do
    let_it_be(:parent) { create(:group) }
    let_it_be(:custom_role_project) { create(:project, group: parent) }
    let_it_be(:member_role) { create(:member_role, :guest, namespace: parent, name: 'Incident responder') }

    let(:object) { custom_role_project }

    before do
      stub_licensed_features(custom_roles: true)
      create(:project_member, :guest, project: custom_role_project, user: user, member_role: member_role)
    end

    # Custom role names are not resolved, because the badge renders from permission_integer.
    it 'reports the base role name rather than the custom role name' do
      expect(json[:permission]).to eq('Guest')
      expect(json[:permission_integer]).to eq(Gitlab::Access::GUEST)
    end
  end

  context 'when group is linked to a subscription', :saas do
    let(:object) { create(:group_with_plan, plan: :ultimate_plan) }

    it 'returns is_linked_to_subscription as true' do
      expect(json[:is_linked_to_subscription]).to be(true)
    end
  end

  context 'when group is not linked to a subscription', :saas do
    let(:object) { group }

    it 'returns is_linked_to_subscription as false' do
      expect(json[:is_linked_to_subscription]).to be(false)
    end
  end
end
