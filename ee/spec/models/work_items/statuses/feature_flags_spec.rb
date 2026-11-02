# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::FeatureFlags, feature_category: :team_planning do
  let_it_be(:namespace) { create(:group) }

  describe '.status_flag_gated_base_types' do
    it 'includes epic and ticket' do
      expect(described_class.status_flag_gated_base_types).to include('epic', 'ticket')
    end

    it 'does not include always-enabled types' do
      expect(described_class.status_flag_gated_base_types).not_to include('issue', 'task')
    end
  end

  describe '.status_enabled_for_base_type?' do
    context 'with a non-flag-gated base type' do
      it 'is always enabled, even without a namespace' do
        expect(described_class.status_enabled_for_base_type?('issue', namespace)).to be(true)
        expect(described_class.status_enabled_for_base_type?('task', nil)).to be(true)
      end
    end

    context 'with a flag-gated base type' do
      it 'is enabled when the flag is on for the namespace' do
        expect(described_class.status_enabled_for_base_type?('epic', namespace)).to be(true)
      end

      it 'is disabled when the flag is off for the namespace' do
        stub_feature_flags(work_item_status_for_epics: false)

        expect(described_class.status_enabled_for_base_type?('epic', namespace)).to be(false)
      end

      it 'is disabled when the namespace cannot be resolved' do
        expect(described_class.status_enabled_for_base_type?('epic', nil)).to be(false)
      end
    end

    context 'with the ticket base type' do
      it 'is enabled when the ticket migration flag is on for the namespace' do
        expect(described_class.status_enabled_for_base_type?('ticket', namespace)).to be(true)
      end

      it 'is disabled when the ticket migration flag is off for the namespace' do
        stub_feature_flags(work_item_ticket_migration: false)

        expect(described_class.status_enabled_for_base_type?('ticket', namespace)).to be(false)
      end

      it 'is disabled when the namespace cannot be resolved' do
        expect(described_class.status_enabled_for_base_type?('ticket', nil)).to be(false)
      end
    end
  end

  describe '.write_status_row?' do
    context 'when the namespace has the status license' do
      before do
        stub_licensed_features(work_item_status: true)
        stub_feature_flags(work_item_status_rows_without_license: false)
      end

      it 'is enabled for a non-flag-gated type' do
        expect(described_class.write_status_row?('issue', namespace)).to be(true)
      end

      it 'follows the per-type flag for a flag-gated type' do
        expect(described_class.write_status_row?('epic', namespace)).to be(true)

        stub_feature_flags(work_item_status_for_epics: false)

        expect(described_class.write_status_row?('epic', namespace)).to be(false)
      end
    end

    context 'when the namespace has no status license' do
      before do
        stub_licensed_features(work_item_status: false)
      end

      it 'is enabled when rows are written without a license' do
        expect(described_class.write_status_row?('issue', namespace)).to be(true)
      end

      it 'is disabled when rows are not written without a license' do
        stub_feature_flags(work_item_status_rows_without_license: false)

        expect(described_class.write_status_row?('issue', namespace)).to be(false)
      end

      it 'is disabled for a flag-gated type' do
        expect(described_class.write_status_row?('epic', namespace)).to be(false)
      end
    end

    it 'is disabled when the namespace cannot be resolved' do
      expect(described_class.write_status_row?('issue', nil)).to be(false)
    end
  end

  describe '.write_rows_without_license?' do
    it 'is enabled for a non-flag-gated type when the flag is on for the namespace' do
      expect(described_class.write_rows_without_license?('issue', namespace)).to be(true)
    end

    it 'is disabled when the flag is off for the namespace' do
      stub_feature_flags(work_item_status_rows_without_license: false)

      expect(described_class.write_rows_without_license?('issue', namespace)).to be(false)
    end

    it 'is disabled for a flag-gated type' do
      expect(described_class.write_rows_without_license?('epic', namespace)).to be(false)
    end

    it 'is disabled when the namespace cannot be resolved' do
      expect(described_class.write_rows_without_license?('issue', nil)).to be(false)
    end
  end
end
