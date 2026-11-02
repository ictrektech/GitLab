# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/secure/show', feature_category: :secrets_management do
  let(:group) { build_stubbed(:group) }
  let(:secrets_manager_setting_available) { true }

  let(:paid_description) do
    s_('SecretsManager|Enable GitLab Secrets Manager for all groups and projects within this namespace.')
  end

  let(:self_managed_description) do
    s_('SecretsManagerPermissions|Store secrets in the secrets manager, ' \
      'which can then be fetched by any project in this group and its subgroups.')
  end

  before do
    assign(:group, group)
    allow(view).to receive(:current_user).and_return(build_stubbed(:user))
    # Isolate this view's own chrome; the partials have their own specs.
    stub_template 'groups/settings/_dependency_firewall.html.haml' => ''
    stub_template 'groups/settings/_secret_manager.html.haml' => ''
    stub_saas_features(gitlab_com_subscriptions: true)
    # The availability decision (realm, enrollability, provisioning state) is
    # covered by the SecretsManagement::Availability.namespace_configurable? spec.
    allow(::SecretsManagement::Availability).to receive(:namespace_configurable?).with(group)
      .and_return(secrets_manager_setting_available)
  end

  context 'when the Secrets Manager setting is available for a top-level group' do
    it 'renders the block with the heading, New badge, anchor id, and SaaS description', :aggregate_failures do
      render

      expect(rendered).to have_css('section#js-secrets-manager-settings')
      expect(rendered).to have_content(s_('SecretsManager|GitLab Secrets Manager'))
      expect(rendered).to have_content(_('New'))
      expect(rendered).to have_content(paid_description)
    end
  end

  context 'when the group is not enrollable (self-managed top-level group)' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it 'renders the self-managed feature description', :aggregate_failures do
      render

      expect(rendered).to have_content(self_managed_description)
      expect(rendered).not_to have_content(paid_description)
    end
  end

  context 'when the Secrets Manager setting is not available' do
    let(:secrets_manager_setting_available) { false }

    it 'does not render the Secrets Manager settings block' do
      render

      expect(rendered).not_to have_css('section#js-secrets-manager-settings')
    end
  end
end
