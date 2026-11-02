# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemVersionDependency, feature_category: :ai_catalog_curation do
  describe 'associations' do
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:dependency).required.inverse_of(:dependents) }
    it { is_expected.to belong_to(:dependency_version).class_name('Ai::Catalog::ItemVersion').optional }
    it { is_expected.to belong_to(:ai_catalog_item_version).required }
  end

  describe 'validations' do
    subject { create(:ai_catalog_item_version_dependency) }

    it { is_expected.to validate_uniqueness_of(:dependency_id).scoped_to(:ai_catalog_item_version_id) }

    it 'rejects a second row for the same dependency item even when pinned differently' do
      existing = create(:ai_catalog_item_version_dependency)
      duplicate = build(:ai_catalog_item_version_dependency, :with_pinned_version,
        ai_catalog_item_version: existing.ai_catalog_item_version,
        organization: existing.organization,
        dependency: existing.dependency
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:dependency_id]).to include('has already been taken')
    end

    describe '#dependency_version_belongs_to_dependency' do
      it 'is valid without a pinned version' do
        expect(build(:ai_catalog_item_version_dependency, dependency_version: nil)).to be_valid
      end

      it 'is valid when the pinned version belongs to the dependency item' do
        record = build(:ai_catalog_item_version_dependency, :with_pinned_version)

        expect(record).to be_valid
      end

      it 'is invalid when the pinned version belongs to another item' do
        record = build(:ai_catalog_item_version_dependency,
          dependency_version: create(:ai_catalog_item_version, :for_agent)
        )

        expect(record).not_to be_valid
        expect(record.errors[:dependency_version]).to include('must be a version of the dependency item')
      end
    end
  end

  describe 'pinned version foreign key' do
    it 'rejects a version of another item at the database level' do
      existing = create(:ai_catalog_item_version_dependency)
      other_version = create(:ai_catalog_item_version, :for_agent)

      expect { existing.update_column(:dependency_version_id, other_version.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'blocks deleting a version while a dependency row pins it' do
      existing = create(:ai_catalog_item_version_dependency, :with_pinned_version)
      pinned = existing.dependency_version
      # The item must point its latest_version somewhere else before the
      # pinned version can be deleted
      create(:ai_catalog_item_version, :for_agent, item: pinned.item)

      expect { pinned.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
