# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "groups/security/policies/index", feature_category: :security_policy_management do
  let_it_be(:user) { build_stubbed(:user) }
  let_it_be(:group) { build_stubbed(:group, namespace_settings: build_stubbed(:namespace_settings)) }

  let(:designated_as_csp) { false }

  before do
    allow(view).to receive(:current_user).and_return(user)
    # Reads the organization's policy settings, which an unsaved group has none of.
    allow(group).to receive(:designated_as_csp?).and_return(designated_as_csp)

    render template: 'groups/security/policies/index', locals: { group: group }
  end

  it 'renders the security policies list root' do
    expect(rendered).to have_selector('#js-group-security-policies-list')
  end

  it 'passes the group-only data attributes', :aggregate_failures do
    expect(rendered).to have_selector(
      "#js-group-security-policies-list[data-namespace-path='#{group.full_path}']"
    )
    expect(rendered).to have_selector(
      "#js-group-security-policies-list[data-root-namespace-path='#{group.root_ancestor.full_path}']"
    )
    expect(rendered).to have_selector("#js-group-security-policies-list[data-designated-as-csp='false']")
  end

  context 'when the group is designated as CSP' do
    let(:designated_as_csp) { true }

    it 'stringifies the flag into the dataset' do
      expect(rendered).to have_selector("#js-group-security-policies-list[data-designated-as-csp='true']")
    end
  end
end
