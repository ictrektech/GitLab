# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::AutoDisabling, feature_category: :webhooks do
  describe '.auto_disabling_feature_enabled?' do
    it 'reads the flag once per request', :request_store do
      allow(Feature).to receive(:enabled?).and_call_original

      2.times { SystemHook.auto_disabling_feature_enabled? }

      expect(Feature).to have_received(:enabled?).with(:auto_disabling_web_hooks, type: :ops).once
    end
  end
end
