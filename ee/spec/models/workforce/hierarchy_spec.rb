# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Workforce::Hierarchy, feature_category: :value_stream_management do
  describe 'associations' do
    it { is_expected.to belong_to(:integration).optional }
    it { is_expected.to belong_to(:group).optional }
    it { is_expected.to belong_to(:organization).class_name('Organizations::Organization').optional }
    it { is_expected.to have_many(:people).class_name('Workforce::Person') }
  end

  describe 'validations' do
    it 'accepts a group-level tenant' do
      expect(build(:workforce_hierarchy)).to be_valid
    end

    it 'accepts an instance-level tenant' do
      expect(build(:workforce_hierarchy, :instance_level)).to be_valid
    end

    it 'rejects a subgroup as the tenant' do
      hierarchy = build(:workforce_hierarchy, group: create(:group, parent: create(:group)))

      expect(hierarchy).not_to be_valid
      expect(hierarchy.errors[:group]).to include('must be a top level Group')
    end

    it 'rejects a hierarchy with no tenant' do
      hierarchy = build(:workforce_hierarchy, group: nil)

      expect(hierarchy).not_to be_valid
      expect(hierarchy.errors[:base]).to include('Exactly one of group_id, organization_id must be present')
    end

    it 'rejects a hierarchy with both a group and an organization' do
      hierarchy = build(:workforce_hierarchy, organization: create(:organization))

      expect(hierarchy).not_to be_valid
      expect(hierarchy.errors[:base]).to include('Exactly one of group_id, organization_id must be present')
    end
  end

  describe 'tenant uniqueness' do
    it 'rejects a second hierarchy for the same group' do
      group = create(:group)
      create(:workforce_hierarchy, group: group)

      expect { create(:workforce_hierarchy, group: group) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects a second hierarchy for the same organization' do
      organization = create(:organization)
      create(:workforce_hierarchy, :instance_level, organization: organization)

      expect do
        create(:workforce_hierarchy, :instance_level, organization: organization)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.delete_for_tenant' do
    let_it_be(:group_hierarchy) { create(:workforce_hierarchy) }
    let_it_be(:organization_hierarchy) { create(:workforce_hierarchy, :instance_level) }
    let_it_be(:other_hierarchy) { create(:workforce_hierarchy) }

    before do
      stub_const('BatchDeleteDependentAssociations::DEPENDENT_ASSOCIATIONS_BATCH_SIZE', 2)

      create_list(:workforce_person, 3, hierarchy: group_hierarchy)
      create(:workforce_person, hierarchy: organization_hierarchy)
      create(:workforce_person, hierarchy: other_hierarchy)
    end

    it 'deletes the group hierarchy and its people in batches, leaving other tenants' do
      expect(Workforce::Person).to receive(:in_hierarchy).with(group_hierarchy).twice.and_call_original

      described_class.delete_for_tenant(group: group_hierarchy.group)

      expect(described_class.all).to contain_exactly(organization_hierarchy, other_hierarchy)
      expect(Workforce::Person.pluck(:workforce_hierarchy_id))
        .to contain_exactly(organization_hierarchy.id, other_hierarchy.id)
    end

    it 'deletes the organization hierarchy and its people, leaving other tenants' do
      described_class.delete_for_tenant(organization: organization_hierarchy.organization)

      expect(described_class.all).to contain_exactly(group_hierarchy, other_hierarchy)
      expect(Workforce::Person.in_hierarchy(organization_hierarchy)).to be_empty
    end

    it 'does nothing for a group without a hierarchy' do
      expect { described_class.delete_for_tenant(group: create(:group)) }
        .not_to change { [described_class.count, Workforce::Person.count] }
    end
  end

  describe 'attribute minimisation' do
    it 'stores no email' do
      expect(described_class.column_names).to all(exclude('email'))
    end
  end
end
