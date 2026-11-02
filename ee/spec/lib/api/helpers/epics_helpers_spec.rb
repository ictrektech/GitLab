# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Helpers::EpicsHelpers, feature_category: :portfolio_management do
  let_it_be(:helper, freeze: false) do
    Class.new.include(API::Helpers).include(described_class).new
  end

  let_it_be(:group) { create(:group) }
  let_it_be(:epic) { create(:epic, group: group) }

  before do
    allow(helper).to receive_messages(user_group: group, epic: epic)
  end

  describe '#authorize_can_update!' do
    it 'authorizes update_epic on the epic' do
      expect(helper).to receive(:authorize!).with(:update_epic, epic)

      helper.authorize_can_update!
    end
  end

  describe '#authorize_can_create!' do
    it 'authorizes create_epic on the group' do
      expect(helper).to receive(:authorize!).with(:create_epic, group)

      helper.authorize_can_create!
    end
  end
end
