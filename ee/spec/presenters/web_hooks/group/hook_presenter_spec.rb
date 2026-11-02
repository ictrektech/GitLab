# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::Group::HookPresenter do
  let(:web_hook) { build_stubbed(:group_hook) }
  let(:web_hook_log) { build_stubbed(:web_hook_log, web_hook: web_hook) }
  let(:group) { web_hook_log.web_hook.group }

  describe '#logs_details_path' do
    subject { web_hook.present.logs_details_path(web_hook_log) }

    let(:expected_path) do
      "/groups/#{group.name}/-/hooks/#{web_hook.id}/hook_logs/#{web_hook_log.id}"
    end

    it { is_expected.to eq(expected_path) }
  end

  describe '#logs_retry_path' do
    subject { web_hook.present.logs_retry_path(web_hook_log) }

    let(:expected_path) do
      "/groups/#{group.name}/-/hooks/#{web_hook.id}/hook_logs/#{web_hook_log.id}/retry"
    end

    it { is_expected.to eq(expected_path) }
  end
end
