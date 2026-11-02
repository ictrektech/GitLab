# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::Storage::NamespaceLimitMailer, feature_category: :consumables_cost_management do
  include EmailSpec::Matchers

  let(:recipients) { %w[bob@example.com john@example.com] }
  let(:namespace) { build_stubbed(:namespace) }
  let(:usage_quotas_link) do
    ActionController::Base.helpers.link_to(namespace.name, usage_quotas_url(namespace, anchor: 'storage-quota-tab'))
  end

  let(:more_storage_url) do
    ::Gitlab::Utils.add_url_parameters(
      ::Gitlab::Routing.url_helpers.subscription_portal_more_storage_url,
      gl_namespace_id: namespace.id
    )
  end

  shared_examples 'group purchase link' do
    it { is_expected.to have_body_text buy_storage_subscriptions_url(selected_group: namespace.id) }

    context 'on GitLab.com', :saas do
      it { is_expected.to have_body_text more_storage_url }
      it { is_expected.to have_text_part_content more_storage_url }

      context 'when customers_dot_addon_ctas is disabled' do
        before do
          stub_feature_flags(customers_dot_addon_ctas: false)
        end

        it { is_expected.to have_body_text buy_storage_subscriptions_url(selected_group: namespace.id) }
      end
    end
  end

  describe '#notify_out_of_storage' do
    subject(:mail) do
      described_class.notify_out_of_storage(namespace: namespace, recipients: recipients,
        usage_values: {
          current_size: 101.megabytes,
          limit: 100.megabytes,
          usage_ratio: 1.01
        })
    end

    it 'creates an email message for a namespace', :aggregate_failures do
      expect(mail).to have_subject "Action required: Storage has been exceeded for #{namespace.name}"
      expect(mail).to bcc_to recipients
      expect(mail).to have_body_text(
        "You have used 101% of the storage quota for #{usage_quotas_link} (101 MiB of 100 MiB)"
      )
      expect(mail).to have_body_text more_storage_url
    end

    context 'when it is a group' do
      let(:namespace) { build_stubbed(:group) }

      it_behaves_like 'group purchase link'
    end
  end

  describe '#notify_limit_warning' do
    subject(:mail) do
      described_class.notify_limit_warning(namespace: namespace, recipients: recipients,
        usage_values: {
          current_size: 75.megabytes,
          limit: 100.megabytes,
          usage_ratio: 0.75
        })
    end

    it 'creates an email message for a namespace', :aggregate_failures do
      expect(mail).to have_subject "You have used 75% of the storage quota for #{namespace.name}"
      expect(mail).to bcc_to recipients
      expect(mail).to have_body_text(
        "You have used 75% of the storage quota for #{usage_quotas_link} (75 MiB of 100 MiB)"
      )
      expect(mail).to have_body_text more_storage_url
    end

    context 'when it is a group' do
      let(:namespace) { build_stubbed(:group) }

      it_behaves_like 'group purchase link'
    end
  end
end
