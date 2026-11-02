# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Loaders::Ai::Catalog::ItemWithProjectLoader, feature_category: :ai_catalog_curation do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:projects) { create_list(:project, 3, group: group) }
  let_it_be(:items) { projects.map { |project| create(:ai_catalog_item, project: project) } }
  let_it_be(:item_without_project) { create(:ai_catalog_item, project: nil) }

  def load(records)
    records.map { |item| described_class.new(item, user).find }.map(&:sync)
  end

  it 'returns the items themselves' do
    expect(load(items)).to eq(items)
  end

  it 'returns an item that has no project' do
    expect(load([item_without_project])).to eq([item_without_project])
  end

  it 'loads the project, its organization, route and setting for every item in one batch' do
    loaded = load(items)

    expect(loaded.map(&:project)).to eq(projects)
    expect(loaded).to all(satisfy { |item| item.association(:project).loaded? })
    expect(loaded).to all(satisfy { |item| item.association(:organization).loaded? })
    expect(loaded.map(&:project)).to all(satisfy { |project| project.association(:route).loaded? })
    expect(loaded.map(&:project)).to all(satisfy { |project| project.association(:project_setting).loaded? })
    expect(loaded.map(&:project)).to all(satisfy { |project| project.namespace.association(:route).loaded? })
  end

  it 'does not run more queries for more items' do
    control = ActiveRecord::QueryRecorder.new(skip_cached: false) { load(items.first(1)) }
    BatchLoader::Executor.clear_current

    expect { load(items) }.not_to exceed_all_query_limit(control)
  end
end
