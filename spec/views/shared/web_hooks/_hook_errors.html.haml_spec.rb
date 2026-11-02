# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/web_hooks/_hook_errors', feature_category: :webhooks do
  before do
    allow(hook).to receive_messages(rate_limited?: true, rate_limit: 1_000)

    render 'shared/web_hooks/hook_errors', hook: hook
  end

  context 'when a system hook is rate limited', :skip_html_escaped_tags_check do
    let(:organization) { build_stubbed(:organization, name: '<b>Acme</b>') }
    let(:hook) { build_stubbed(:system_hook, organization: organization) }

    it 'renders the alert with the organization name', :aggregate_failures do
      expect(rendered).to have_text(s_('Webhooks|Webhook rate limit has been reached'))
      expect(rendered).to have_text(
        format(
          s_("Webhooks|System hooks for %{organization} are now disabled because they've been triggered more " \
            "than %{limit} times per minute. These system hooks are re-enabled automatically in the next minute."),
          organization: organization.name, limit: '1,000'
        )
      )
    end

    it 'escapes the organization name' do
      expect(rendered).to include('&lt;b&gt;Acme&lt;/b&gt;')
    end
  end

  context 'when a project hook is rate limited' do
    let(:project) { build_stubbed(:project) }
    let(:hook) { build_stubbed(:project_hook, project: project) }

    it 'renders the alert with the root namespace path' do
      expect(rendered).to have_text(
        format(
          s_("Webhooks|Webhooks for %{root_namespace} are now disabled because they've been triggered more " \
            "than %{limit} times per minute. These webhooks are re-enabled automatically in the next minute."),
          root_namespace: project.root_namespace.path, limit: '1,000'
        )
      )
    end
  end
end
