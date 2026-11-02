# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItemPresenter, feature_category: :portfolio_management do
  let(:user) { build_stubbed(:user) }
  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- spec needs work_item's namespace persisted to the database
  let_it_be(:project) { create(:project) }
  let_it_be(:original_work_item) { create(:work_item, project: project) }
  # rubocop:enable RSpec/FactoryBot/AvoidCreate
  let(:target_work_item) { build_stubbed(:work_item, project: project) }
  let(:target_work_item_url) { Gitlab::UrlBuilder.build(target_work_item) }

  subject(:presenter) { described_class.new(original_work_item, current_user: user) }

  it 'presents a work item and uses methods defined in IssuePresenter' do
    expect(presenter.issue_path).to eq(presenter.web_path)
  end

  shared_examples 'returns target work item url based on permissions' do
    context 'when anonymous' do
      let(:user) { nil }

      it { is_expected.to be_nil }
    end

    context 'with signed in user' do
      before do
        stub_member_access_level(project, access_level => user) if access_level
      end

      context 'when user has no role in project' do
        let(:access_level) { nil }

        it { is_expected.to be_nil }
      end

      context 'when user has guest role in project' do
        let(:access_level) { :guest }

        it { is_expected.to eq(target_work_item_url) }
      end

      context 'when user has reporter role in project' do
        let(:access_level) { :reporter }

        it { is_expected.to eq(target_work_item_url) }
      end

      context 'when user has developer role in project' do
        let(:access_level) { :developer }

        it { is_expected.to eq(target_work_item_url) }
      end
    end
  end

  describe '#web_url' do
    it 'returns the URL under the project' do
      expect(presenter.web_url)
        .to eq("#{Gitlab.config.gitlab.url}/#{project.full_path}/-/work_items/#{original_work_item.iid}")
    end

    context 'with a group work item' do
      let(:group) { build_stubbed(:group) }
      let(:original_work_item) { build_stubbed(:work_item, namespace: group) }

      it 'returns the URL under the group' do
        expect(presenter.web_url)
          .to eq("#{Gitlab.config.gitlab.url}/groups/#{group.full_path}/-/work_items/#{original_work_item.iid}")
      end
    end
  end

  describe '#duplicated_to_work_item_url' do
    subject { presenter.duplicated_to_work_item_url }

    it { is_expected.to be_nil }

    it_behaves_like 'returns target work item url based on permissions' do
      let(:original_work_item) { build_stubbed(:work_item, project: project, duplicated_to: target_work_item) }
    end
  end

  describe '#moved_to_work_item_url' do
    subject { presenter.moved_to_work_item_url }

    it { is_expected.to be_nil }

    it_behaves_like 'returns target work item url based on permissions' do
      # Create original work item in other project
      let(:original_work_item) { build_stubbed(:work_item, moved_to: target_work_item) }
    end
  end

  describe '#moved_to_work_item_id' do
    subject { presenter.moved_to_work_item_id }

    it { is_expected.to be_nil }

    context 'when the work item was moved' do
      let(:original_work_item) { build_stubbed(:work_item, moved_to: target_work_item) }

      context 'when anonymous' do
        let(:user) { nil }

        it { is_expected.to be_nil }
      end

      context 'when user has no role in the target project' do
        it { is_expected.to be_nil }
      end

      context 'when user has guest role in the target project' do
        before do
          stub_member_access_level(project, guest: user)
        end

        it { is_expected.to eq(target_work_item.id) }

        # Both fields share one memoized lookup, so requesting them together
        # checks read access to the target work item only once.
        it 'checks read access to the target once when the URL is also read' do
          allow(Ability).to receive(:allowed?).and_call_original
          expect(Ability).to receive(:allowed?).with(user, :read_work_item, target_work_item).once.and_call_original

          presenter.moved_to_work_item_url
          presenter.moved_to_work_item_id
        end
      end
    end
  end
end
