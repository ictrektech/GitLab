# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261014120000_add_active_to_groups.rb')

RSpec.describe AddActiveToGroups, :elastic, feature_category: :global_search do
  let(:version) { 20261014120000 }

  include_examples 'migration adds mapping'

  describe 'the mapping body' do
    let(:migration) { described_class.new(version) }
    let(:helper) { ::Search::Elastic::Helper.new }

    before do
      allow(migration).to receive(:helper).and_return(helper)
      allow(helper).to receive(:get_mapping).and_return({})
    end

    it 'adds a boolean active field to the groups index' do
      expect(helper).to receive(:update_mapping).with(
        index_name: ::Search::Elastic::References::Group.index,
        mappings: { properties: { active: { type: 'boolean' } } }
      )

      migration.migrate
    end
  end
end
