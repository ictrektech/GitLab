# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::SshCertificate, feature_category: :source_code_management do
  subject { build(:group_ssh_certificate) }

  it_behaves_like 'an SSH certificate record', factory_name: :group_ssh_certificate

  describe 'associations' do
    it 'belongs to a group' do
      is_expected.to belong_to(:group).with_foreign_key(:namespace_id).inverse_of(:ssh_certificates)
    end
  end

  describe 'validations' do
    it 'presence of group' do
      is_expected.to validate_presence_of(:group)
    end

    it 'uniqueness of fingerprint scoped to namespace_id' do
      existing = create(:group_ssh_certificate)

      duplicate = build(:group_ssh_certificate, group: existing.group, key: existing.key)
      expect(duplicate).to be_invalid
      expect(duplicate.errors[:fingerprint]).to include(
        'must be unique. This CA has already been configured for this namespace.'
      )

      other_group = create(:group)
      different_namespace = build(:group_ssh_certificate, group: other_group, key: existing.key)
      expect(different_namespace).to be_valid
    end
  end

  describe '.for_namespace' do
    let_it_be(:group) { create(:group) }
    let_it_be(:other_group) { create(:group) }
    let_it_be(:certificate) { create(:group_ssh_certificate, group: group) }
    let_it_be(:other_certificate) { create(:group_ssh_certificate, group: other_group) }

    it 'returns certificates for the given namespace' do
      result = described_class.for_namespace(group.id)

      expect(result).to contain_exactly(certificate)
    end

    it 'excludes certificates belonging to another namespace' do
      result = described_class.for_namespace(other_group.id)

      expect(result).to contain_exactly(other_certificate)
    end

    it 'returns empty when no match' do
      result = described_class.for_namespace(non_existing_record_id)

      expect(result).to be_empty
    end
  end
end
