# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

# Measures subtree resolution against a workforce hierarchy the size of the largest
# tenant we support, which is the acceptance criterion for
# https://gitlab.com/gitlab-org/gitlab/-/work_items/629837.
#
# It is skipped unless BENCHMARK is set: a wall-clock assertion on a shared runner would
# be flaky. Run it locally and paste the numbers into the merge request alongside a
# Database Lab plan.
#
# Run by:
#   BENCHMARK=1 bundle exec rspec ee/spec/models/workforce/person_subtree_benchmark_spec.rb
RSpec.describe Workforce::Person, 'subtree benchmark', if: ENV.key?('BENCHMARK'),
  feature_category: :value_stream_management do
  let(:people_count) { ENV.fetch('COUNT', 50_000).to_i }
  let(:branching) { 7 }
  let(:budget_ms) { 100 }

  # One person per level, so the measurement covers the whole-org read at the root as
  # well as the narrower reads further down that most dashboard filters will issue.
  it 'resolves any manager subtree within the budget' do
    hierarchy = create(:workforce_hierarchy)
    spine = build_tree(hierarchy, people_count, branching)
    ApplicationRecord.connection.execute('ANALYZE workforce_people')

    expect(described_class.in_hierarchy(hierarchy).count).to eq(people_count)

    spine.each_with_index do |person, depth|
      size = described_class.subtree_of(person).count
      elapsed_ms = Benchmark.realtime { described_class.subtree_of(person).pluck(:id) } * 1000

      puts format('depth %<depth>d: %<size>6d people in %<ms>6.1f ms', depth: depth, size: size, ms: elapsed_ms)

      expect(elapsed_ms).to be < budget_ms

      # For a subtree holding a large share of the org, a sequential scan is the cheaper plan.
      next if size > people_count / 10

      expect(query_plan(described_class.subtree_of(person)))
        .to include('index_workforce_people_on_hierarchy_id_and_traversal_ids')
    end
  end

  def query_plan(relation)
    ApplicationRecord.connection.select_rows("EXPLAIN #{relation.to_sql}").flatten.join("\n")
  end

  # Same write pattern as ee/db/fixtures/development/99_workforce_hierarchy.rb, with a fixed
  # span of control: insert a level, then append each row's own id to its manager's path.
  # Returns the leftmost person of each level, root first.
  def build_tree(hierarchy, count, branching)
    created = 0
    sequence = 0
    spine = []
    parents = [nil]
    fanout = 1

    # Not parents.any?: the root level's parent is nil, and [nil].any? is false.
    while created < count && parents.present?
      rows = []

      parents.each do |parent|
        fanout.times do
          break if created + rows.size >= count

          sequence += 1
          rows << {
            workforce_hierarchy_id: hierarchy.id,
            group_id: hierarchy.group_id,
            traversal_ids: parent ? parent[:traversal_ids] : [],
            external_xid: "wd-#{sequence}",
            manager_external_xid: parent && parent[:external_xid],
            full_name: "Person #{sequence}",
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        break if created + rows.size >= count
      end

      break if rows.empty?

      ids = rows.each_slice(5_000).flat_map do |slice|
        described_class.insert_all!(slice, returning: %w[id]).rows.flatten
      end

      described_class.where(id: ids).update_all('traversal_ids = traversal_ids || id')
      created += ids.size
      fanout = branching

      parents = described_class.where(id: ids).pluck(:external_xid, :traversal_ids).map do |xid, path|
        { external_xid: xid, traversal_ids: path }
      end

      spine << described_class.find_by(
        workforce_hierarchy_id: hierarchy.id, external_xid: parents.first[:external_xid]
      )
    end

    spine
  end
end
