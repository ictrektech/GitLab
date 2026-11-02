# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillNamespaceAiSettingsConfiguredAt,
  feature_category: :compliance_management, time_travel_to: '2026-10-26T12:00:00Z' do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:ai_settings) { table(:namespace_ai_settings) }

  let!(:organization) { organizations.create!(name: 'Organization', path: 'organization') }
  let!(:group) { create_group }

  let(:backfill_time) { '2026-10-26T12:00:00Z' }
  let(:older) { '2026-09-01T10:00:00Z' }
  let(:newer) { '2026-10-27T10:00:00Z' }
  let(:fully_backfilled) do
    {
      'duo_workflow_mcp_enabled' => backfill_time,
      'ai_usage_data_collection_enabled' => backfill_time,
      'ai_catalog_restricted_to_group_hierarchy' => backfill_time,
      'web_search_enabled' => backfill_time,
      'prompt_injection_protection_level' => backfill_time
    }
  end

  let(:sub_batch_size) { 100 }

  subject(:migration) do
    described_class.new(
      start_cursor: [ai_settings.minimum(:namespace_id)],
      end_cursor: [ai_settings.maximum(:namespace_id)],
      batch_table: :namespace_ai_settings,
      batch_column: :namespace_id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: ::ApplicationRecord.connection
    )
  end

  describe '#perform' do
    it 'writes all five tracked keys with the backfill time' do
      migration.perform

      expect(configured_at_for(group)).to eq(fully_backfilled)
    end

    it 'fills only the missing keys' do
      stamp(group, 'duo_workflow_mcp_enabled' => older, 'web_search_enabled' => newer)

      migration.perform

      expect(configured_at_for(group)).to eq(
        fully_backfilled.merge('duo_workflow_mcp_enabled' => older, 'web_search_enabled' => newer)
      )
    end

    it 'preserves unrelated existing keys' do
      stamp(group, 'unrelated' => older)

      migration.perform

      expect(configured_at_for(group)).to eq(fully_backfilled.merge('unrelated' => older))
    end

    it 'does not inspect the current setting values' do
      customized_group = create_group(
        duo_workflow_mcp_enabled: true,
        ai_usage_data_collection_enabled: true,
        ai_catalog_restricted_to_group_hierarchy: true,
        web_search_enabled: true,
        prompt_injection_protection_level: 2
      )

      migration.perform

      expect(configured_at_for(group)).to eq(fully_backfilled)
      expect(configured_at_for(customized_group)).to eq(fully_backfilled)
    end

    # Every UPDATE writes a new tuple and so changes ctid, even when the value is unchanged.
    it 'does not rewrite rows that already have all five keys' do
      stamp(group, fully_backfilled.transform_values { older })
      ctid = -> { ai_settings.where(namespace_id: group.id).pick(Arel.sql('ctid::text')) }

      expect { migration.perform }.not_to change { ctid.call }
    end

    it 'does not touch feature_settings' do
      ai_settings.where(namespace_id: group.id).update_all(feature_settings: { duo_agent_platform_enabled: false })

      migration.perform

      settings = ai_settings.find_by(namespace_id: group.id)
      expect(settings.feature_settings).to eq('duo_agent_platform_enabled' => false)
      expect(settings.configured_at).not_to have_key('duo_agent_platform_enabled')
    end

    it 'is idempotent' do
      migration.perform
      first_run = configured_at_for(group)

      travel_to(1.day.from_now)
      migration.perform

      expect(configured_at_for(group)).to eq(first_run)
    end

    it 'produces a configured_at value that passes model validation' do
      migration.perform

      expect(::Ai::NamespaceSetting.find(group.id)).to be_valid
    end

    context 'with several sub-batches' do
      let(:sub_batch_size) { 1 }

      it 'backfills every row that misses keys and skips fully stamped rows' do
        stamped_group = create_group
        last_group = create_group
        stamp(stamped_group, fully_backfilled.transform_values { older })
        ctid = -> { ai_settings.where(namespace_id: stamped_group.id).pick(Arel.sql('ctid::text')) }

        expect { migration.perform }.not_to change { ctid.call }

        expect(configured_at_for(group)).to eq(fully_backfilled)
        expect(configured_at_for(last_group)).to eq(fully_backfilled)
      end
    end
  end

  def configured_at_for(namespace)
    ai_settings.find_by(namespace_id: namespace.id).configured_at
  end

  def stamp(namespace, configured_at)
    ai_settings.where(namespace_id: namespace.id).update_all(configured_at: configured_at)
  end

  def create_group(**settings)
    path = "group-#{SecureRandom.hex(4)}"
    namespace = namespaces.create!(name: path, path: path, type: 'Group', organization_id: organization.id)
    ai_settings.create!(namespace_id: namespace.id, **settings)
    namespace
  end
end
