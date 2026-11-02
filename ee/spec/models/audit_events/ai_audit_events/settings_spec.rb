# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::AiAuditEvents::Settings, feature_category: :audit_events do
  describe '.storage_enabled?' do
    subject { described_class.storage_enabled?(resource) }

    let_it_be_with_reload(:project) { create(:project) }
    let_it_be_with_reload(:group) { create(:group) }

    context 'with a project' do
      let(:resource) { project }

      it { is_expected.to be(false) }

      context 'when storage is enabled' do
        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: true)
        end

        it { is_expected.to be(true) }
      end

      context 'when storage is explicitly disabled' do
        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: false)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'with a namespace' do
      let(:resource) { group }

      it { is_expected.to be(false) }

      context 'when storage is enabled' do
        before do
          group.namespace_settings.update!(ai_audit_events_storage_enabled: true)
        end

        it { is_expected.to be(true) }
      end
    end

    context 'without a project or namespace' do
      let(:resource) { nil }

      it { is_expected.to be(false) }
    end
  end

  describe '.streaming_enabled?' do
    subject { described_class.streaming_enabled?(organization) }

    let_it_be(:organization) { create(:organization) }

    it { is_expected.to be(false) }

    context 'when streaming is enabled for the organization' do
      before do
        ::Ai::Setting.for_organization(organization).update!(ai_audit_events_streaming_enabled: true)
      end

      it { is_expected.to be(true) }
    end

    context 'without an organization' do
      let(:organization) { nil }

      it { is_expected.to be(false) }
    end
  end
end
