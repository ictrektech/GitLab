# frozen_string_literal: true

require 'fast_spec_helper'
require 'gitlab/safe_request_store'

RSpec.describe Gitlab::EpicWorkItemSync::Logger, feature_category: :team_planning do
  describe '.build' do
    it 'builds an instance' do
      expect(described_class.build).to be_an_instance_of(described_class)
    end
  end

  describe '.file_name_noext' do
    it 'sets correct filename' do
      expect(described_class.file_name_noext).to eq('epic_work_item_sync')
    end
  end
end
