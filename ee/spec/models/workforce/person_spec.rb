# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Workforce::Person, feature_category: :value_stream_management do
  describe 'associations' do
    it 'belongs to a hierarchy' do
      is_expected.to belong_to(:hierarchy)
        .class_name('Workforce::Hierarchy').with_foreign_key(:workforce_hierarchy_id).inverse_of(:people).required
    end

    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:group).optional }
    it { is_expected.to belong_to(:organization).class_name('Organizations::Organization').optional }
  end

  describe 'validations' do
    subject { build(:workforce_person) }

    it { is_expected.to validate_presence_of(:external_xid) }
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_length_of(:external_xid).is_at_most(255) }
    it { is_expected.to validate_length_of(:manager_external_xid).is_at_most(255) }
    it { is_expected.to validate_length_of(:full_name).is_at_most(255) }

    it 'rejects a subgroup as the tenant' do
      person = build(:workforce_person, group: create(:group, parent: create(:group)))

      expect(person).not_to be_valid
      expect(person.errors[:group]).to include('must be a top level Group')
    end
  end

  describe 'sharding key' do
    it 'takes the group of a group-level hierarchy' do
      person = create(:workforce_person)

      expect(person.group_id).to eq(person.hierarchy.group_id)
      expect(person.organization_id).to be_nil
    end

    it 'takes the organization of an instance-level hierarchy' do
      hierarchy = create(:workforce_hierarchy, :instance_level)
      person = create(:workforce_person, hierarchy: hierarchy)

      expect(person.organization_id).to eq(hierarchy.organization_id)
      expect(person.group_id).to be_nil
    end
  end

  describe 'uniqueness' do
    let_it_be(:hierarchy) { create(:workforce_hierarchy) }

    it 'rejects a duplicate external xid within a hierarchy' do
      create(:workforce_person, hierarchy: hierarchy, external_xid: 'wd-1')

      expect do
        create(:workforce_person, hierarchy: hierarchy, external_xid: 'wd-1')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same external xid in a different hierarchy' do
      create(:workforce_person, hierarchy: hierarchy, external_xid: 'wd-1')

      expect do
        create(:workforce_person, hierarchy: create(:workforce_hierarchy), external_xid: 'wd-1')
      end.not_to raise_error
    end

    it 'rejects a second person matched to the same user within a hierarchy' do
      user = create(:user)
      create(:workforce_person, hierarchy: hierarchy, user: user)

      expect do
        create(:workforce_person, hierarchy: hierarchy, user: user)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows many unmatched people within a hierarchy' do
      create_list(:workforce_person, 2, :unmatched, hierarchy: hierarchy)

      expect(hierarchy.people.count).to eq(2)
    end
  end

  describe 'attribute minimisation' do
    it 'stores no email' do
      expect(described_class.column_names).to all(exclude('email'))
    end
  end

  context 'with a tree' do
    let_it_be(:hierarchy) { create(:workforce_hierarchy) }
    let_it_be(:ceo) { create_person(hierarchy) }
    let_it_be(:vp) { create_person(hierarchy, manager: ceo) }
    let_it_be(:director) { create_person(hierarchy, manager: vp) }
    let_it_be(:engineer) { create_person(hierarchy, manager: director) }
    let_it_be(:other_vp) { create_person(hierarchy, manager: ceo) }

    describe '.subtree_of' do
      it 'returns the person and everyone below them' do
        expect(described_class.subtree_of(vp)).to contain_exactly(vp, director, engineer)
      end

      it 'returns nothing for a person whose path is not written yet' do
        expect(described_class.subtree_of(create(:workforce_person, hierarchy: hierarchy))).to be_empty
      end

      it 'returns only the person for a leaf' do
        expect(described_class.subtree_of(engineer)).to contain_exactly(engineer)
      end

      it 'returns the whole tree for the root' do
        expect(described_class.subtree_of(ceo))
          .to contain_exactly(ceo, vp, director, engineer, other_vp)
      end
    end

    describe '.direct_reports_of' do
      it 'returns only the people reporting straight into the manager' do
        expect(described_class.direct_reports_of(ceo)).to contain_exactly(vp, other_vp)
      end
    end
  end

  describe 'matching scopes' do
    let_it_be(:hierarchy) { create(:workforce_hierarchy) }
    let_it_be(:user) { create(:user) }
    let_it_be(:matched) { create(:workforce_person, hierarchy: hierarchy, user: user) }
    let_it_be(:unmatched) { create(:workforce_person, :unmatched, hierarchy: hierarchy) }

    it { expect(described_class.matched(hierarchy)).to contain_exactly(matched) }
    it { expect(described_class.unmatched(hierarchy)).to contain_exactly(unmatched) }
    it { expect(described_class.for_user(hierarchy, user)).to contain_exactly(matched) }
  end

  describe 'tenant isolation' do
    let_it_be(:hierarchy) { create(:workforce_hierarchy) }
    let_it_be(:other_hierarchy) { create(:workforce_hierarchy, :instance_level) }
    let_it_be(:user) { create(:user) }

    let_it_be(:root) { create_person(hierarchy, external_xid: 'shared-xid') }
    let_it_be(:report) { create_person(hierarchy, manager: root) }
    let_it_be(:matched) { create(:workforce_person, hierarchy: hierarchy, user: user) }

    # Same external identifier, same matched user, and an ancestry path deliberately
    # planted inside the other tenant's subtree.
    let_it_be(:intruder) do
      person = create(:workforce_person, hierarchy: other_hierarchy, user: user, external_xid: 'shared-xid')
      person.update!(traversal_ids: root.traversal_ids + [person.id])
      person
    end

    let_it_be(:unmatched_intruder) do
      create(:workforce_person, :unmatched, hierarchy: other_hierarchy, manager_external_xid: 'shared-xid')
    end

    it 'excludes the other tenant from a subtree read' do
      expect(described_class.subtree_of(root)).to contain_exactly(root, report)
    end

    it 'excludes the other tenant from a direct reports read' do
      expect(described_class.direct_reports_of(root)).to contain_exactly(report)
    end

    it 'resolves a matched user to exactly one person within a tenant' do
      expect(described_class.for_user(hierarchy, user)).to contain_exactly(matched)
      expect(described_class.for_user(other_hierarchy, user)).to contain_exactly(intruder)
    end

    it 'excludes the other tenant from a matched read' do
      expect(described_class.matched(hierarchy)).to contain_exactly(matched)
    end

    it 'excludes the other tenant from an unmatched read' do
      expect(described_class.unmatched(hierarchy)).to contain_exactly(root, report)
    end

    it 'excludes the other tenant from a reverse lookup by user' do
      expect(described_class.for_user(hierarchy, user)).to contain_exactly(matched)
    end
  end

  def create_person(hierarchy, manager: nil, **attrs)
    person = create(:workforce_person, hierarchy: hierarchy, manager_external_xid: manager&.external_xid, **attrs)
    person.update!(traversal_ids: (manager&.traversal_ids || []) + [person.id])
    person
  end
end
