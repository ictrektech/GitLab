# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/web_hooks/_hook.html.haml', feature_category: :integrations do
  let_it_be(:hook) { build_stubbed(:system_hook) }
  let_it_be(:organization) { build_stubbed(:organization) }

  def test_item_hrefs
    items = Nokogiri::HTML(rendered).at_css('.js-webhook-test-dropdown')['data-items']

    Gitlab::Json::SafeParser.parse(items).pluck('href')
  end

  before do
    allow(view).to receive(:can?).and_return(true)
  end

  context 'without an organization' do
    before do
      render partial: 'shared/web_hooks/hook', locals: { hook: hook }
    end

    it 'links to admin hook paths' do
      expect(rendered).to have_link('Edit', href: edit_admin_hook_path(hook))
      expect(rendered).to have_link('Delete', href: admin_hook_path(hook))
      expect(test_item_hrefs).to include(test_admin_hook_path(hook, trigger: :push_events))
    end
  end

  context 'with an organization' do
    before do
      render partial: 'shared/web_hooks/hook', locals: { hook: hook, organization: organization }
    end

    it 'links to organization admin hook paths' do
      expect(rendered).to have_link('Edit', href: edit_organization_admin_settings_hook_path(organization, hook))
      expect(rendered).to have_link('Delete', href: organization_admin_settings_hook_path(organization, hook))
      expect(test_item_hrefs)
        .to include(test_organization_admin_settings_hook_path(organization, hook, trigger: :push_events))
    end
  end
end
