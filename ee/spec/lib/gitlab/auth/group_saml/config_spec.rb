# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Auth::GroupSaml::Config, feature_category: :system_access do
  describe '.sign_in_enabled?' do
    subject { described_class.sign_in_enabled? }

    it { is_expected.to be(true) }

    context 'when group SAML sign-in is disabled under sign-in restrictions' do
      before do
        stub_application_setting(disabled_oauth_sign_in_sources: ['group_saml'])
      end

      it { is_expected.to be(false) }
    end

    context 'when the group_saml provider is not enabled' do
      before do
        allow(Gitlab::Auth::OAuth::Provider).to receive(:enabled?).with(:group_saml).and_return(false)
      end

      it { is_expected.to be(false) }
    end
  end
end
