# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/FactoryBot/AvoidCreate -- build_stubbed cannot be used with real policy checks that require DB-persisted membership
RSpec.describe 'projects/branch_rules/_show', feature_category: :source_code_management do
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }
  let_it_be(:user, freeze: false) { create(:user) }

  let(:listing_data) { Nokogiri::HTML(rendered).at_css('#js-branch-rules-listing') }

  before do
    stub_licensed_features(custom_roles: true, external_status_checks: true, merge_request_approvers: true)

    assign :project, project
    allow(view).to receive(:current_user).and_return(user)
  end

  shared_examples 'branch rule listing permissions' do |create_branch_rule:, create_approval_rule:,
    create_status_check:|
    it 'passes the create permissions to the listing app' do
      render

      expect(listing_data['data-can-create-branch-rule']).to eq(create_branch_rule.to_s)
      expect(listing_data['data-can-create-approval-rule']).to eq(create_approval_rule.to_s)
      expect(listing_data['data-can-create-external-status-check']).to eq(create_status_check.to_s)
    end
  end

  context 'when user is a maintainer' do
    before_all do
      project.add_maintainer(user)
    end

    it_behaves_like 'branch rule listing permissions',
      create_branch_rule: true, create_approval_rule: true, create_status_check: true

    context 'when approval rules and status checks are not licensed' do
      before do
        stub_licensed_features(external_status_checks: false, merge_request_approvers: false)
      end

      it_behaves_like 'branch rule listing permissions',
        create_branch_rule: true, create_approval_rule: false, create_status_check: false
    end
  end

  context 'when user is a developer' do
    before_all do
      project.add_developer(user)
    end

    it_behaves_like 'branch rule listing permissions',
      create_branch_rule: false, create_approval_rule: false, create_status_check: false
  end

  context 'when user is a guest with a custom role' do
    let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }

    context 'with manage_merge_request_settings' do
      before_all do
        create(:member_role, :guest, :manage_merge_request_settings, namespace: group, members: [project_member])
      end

      it_behaves_like 'branch rule listing permissions',
        create_branch_rule: false, create_approval_rule: true, create_status_check: true
    end
  end
end
# rubocop:enable RSpec/FactoryBot/AvoidCreate
