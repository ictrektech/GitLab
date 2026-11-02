# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::DuoPro, feature_category: :subscription_management do
  let_it_be(:namespace) { create(:group) }

  describe '.show_duo_usage_settings?' do
    subject { described_class.show_duo_usage_settings?(namespace) }

    context 'when active add_on' do
      let_it_be(:add_on_purchase_on) do
        create(:gitlab_subscription_add_on_purchase, :duo_pro, namespace: namespace)
      end

      it { is_expected.to be(true) }
    end

    context 'when on trial' do
      let_it_be(:add_on_purchase_on) do
        create(:gitlab_subscription_add_on_purchase, :duo_pro, :trial, namespace: namespace)
      end

      it { is_expected.to be(true) }
    end

    context 'when on expired trial' do
      let_it_be(:add_on_purchase_on) do
        create(:gitlab_subscription_add_on_purchase, :duo_pro, :expired_trial, namespace: namespace)
      end

      it { is_expected.to be(true) }
    end

    context 'when on trial expired 11 days ago' do
      let_it_be(:add_on_purchase_on) do
        create(:gitlab_subscription_add_on_purchase, :duo_pro, :trial,
          namespace: namespace,
          expires_on: 11.days.ago
        )
      end

      it { is_expected.to be(false) }
    end

    context 'when namespace does not have an add_on' do
      it { is_expected.to be(false) }
    end
  end
end
