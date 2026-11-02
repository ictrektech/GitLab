# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::ProjectsCounter, feature_category: :user_management do
  describe '#execute' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:organization_group) { create(:group, organization: organization) }
    let_it_be(:user) { create(:user) }
    let_it_be(:user_without_projects) { create(:user) }
    let_it_be(:user_ids) { [user.id, user_without_projects.id] }

    before_all do
      create_list(:project, 3, group: organization_group).each { |project| project.add_developer(user) }
      create(:project).add_developer(user)
    end

    it 'counts all authorized projects for each user' do
      expect(described_class.new(user_ids).execute).to eq(user.id => 4)
    end

    context 'when an organization is given' do
      subject(:counts) { described_class.new(user_ids, organization: organization).execute }

      it 'counts only projects in the organization' do
        expect(counts).to eq(user.id => 3, user_without_projects.id => 0)
      end

      it 'counts only the projects each user is authorized for' do
        other_user = create(:user)
        create(:project, group: organization_group).add_developer(other_user)

        counts = described_class.new([user.id, other_user.id], organization: organization).execute

        expect(counts).to eq(user.id => 3, other_user.id => 1)
      end

      it 'stops counting at one more than the limit' do
        stub_const('Users::ProjectsCounter::COUNT_LIMIT', 1)

        expect(counts).to eq(user.id => 2, user_without_projects.id => 0)
      end
    end
  end
end
