# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::BuildDependencyGraph, :unlimited_max_formatted_output_length, feature_category: :dependency_management do
  matcher :match_path do |ancestor, descendant, project_id, path_length, timestamp, top_level|
    match do |path|
      path.ancestor_id == ancestor \
        && path.descendant_id == descendant \
        && path.project_id == project_id \
        && path.path_length == path_length \
        && path.created_at == timestamp \
        && path.updated_at == timestamp \
        && path.top_level_ancestor == top_level
    end
  end

  describe "base test case" do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:ancestor) { create(:sbom_occurrence, project: project, ancestors: [{}]) }
    let_it_be(:descendant) do
      create(:sbom_occurrence, ancestors: [{ name: ancestor.component_name, version: ancestor.version }, {}],
        input_file_path: ancestor.input_file_path, project: project)
    end

    let_it_be(:grandchild) do
      create(:sbom_occurrence,
        ancestors: [
          { name: descendant.component_name, version: descendant.version }
        ],
        input_file_path: descendant.input_file_path, project: project)
    end

    let_it_be(:grandgrandchild) do
      create(:sbom_occurrence, ancestors: [{ name: grandchild.component_name, version: grandchild.version }],
        input_file_path: grandchild.input_file_path, project: project)
    end

    let_it_be(:deep_one) do
      create(:sbom_occurrence, ancestors: [{ name: grandgrandchild.component_name, version: grandgrandchild.version },
        {}], input_file_path: grandgrandchild.input_file_path, project: project)
    end

    let_it_be(:branch_parent) do
      create(:sbom_occurrence,
        ancestors: [
          { name: descendant.component_name, version: descendant.version },
          { name: grandchild.component_name, version: grandchild.version }
        ],
        input_file_path: descendant.input_file_path, project: project)
    end

    let(:expected_cache_key) { Sbom::LatestGraphTimestampCacheKey.new(project: project).cache_key }

    subject(:service) { described_class.new(project) }

    it "builds a dependency tree", :aggregate_failures, :freeze_time do
      service.execute
      resulting_paths = Sbom::GraphPath.by_projects(project)
      expect(resulting_paths).to contain_exactly(
        match_path(ancestor.id, descendant.id, project.id, 1, service.timestamp, true),
        match_path(descendant.id, grandchild.id, project.id, 1, service.timestamp, true),
        match_path(descendant.id, branch_parent.id, project.id, 1, service.timestamp, true),
        match_path(grandchild.id, grandgrandchild.id, project.id, 1, service.timestamp, false),
        match_path(grandchild.id, branch_parent.id, project.id, 1, service.timestamp, false),
        match_path(grandgrandchild.id, deep_one.id, project.id, 1, service.timestamp, false)
      )
    end

    it "sets the created_at timestamp of all new records to the same timestamp", :freeze_time do
      service.execute
      expect(Sbom::GraphPath.by_projects(project).pluck(:created_at)).to all eq(service.timestamp)
    end

    it "writes latest graph key to cache", :freeze_time do
      now = service.timestamp
      expect(Rails.cache).to receive(:write).with(expected_cache_key, now,
        expires_in: 24.hours).once
      service.execute
    end

    it "invokes the remove job after building the tree" do
      expect(Sbom::RemoveOldDependencyGraphsWorker).to receive(:perform_async).with(project.id)
      service.execute
    end

    it "does not store duplicate graph paths" do
      expect { service.execute }.to change {
        Sbom::GraphPath.by_projects(project).where(ancestor: descendant, descendant: grandchild).count
      }.from(0).to(1)
    end

    it "logs the expected message when the build completes" do
      expect(::Gitlab::AppLogger).to receive(:info).with(
        message: "New graph creation complete",
        project: project.name,
        project_id: project.id,
        namespace: project.group.name,
        namespace_id: project.group.id,
        count_path_nodes: 6
      )
      service.execute
    end
  end

  describe "cyclic paths" do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:cycle_3_sbom_component) { create(:sbom_component) }
    let_it_be(:cycle_3_sbom_component_version) { create(:sbom_component_version, component: cycle_3_sbom_component) }
    let_it_be(:ancestor) { create(:sbom_occurrence, project: project, ancestors: [{}]) }
    let_it_be(:cycle_1) do
      create(:sbom_occurrence,
        ancestors: [
          { name: ancestor.component_name, version: ancestor.version },
          { name: cycle_3_sbom_component.name, version: cycle_3_sbom_component_version.version }
        ],
        input_file_path: ancestor.input_file_path,
        project: project
      )
    end

    let_it_be(:cycle_2) do
      create(:sbom_occurrence,
        ancestors: [{ name: cycle_1.component_name, version: cycle_1.version }],
        input_file_path: cycle_1.input_file_path,
        project: project
      )
    end

    let_it_be(:cycle_3) do
      create(:sbom_occurrence,
        component: cycle_3_sbom_component,
        component_version: cycle_3_sbom_component_version,
        ancestors: [{ name: cycle_2.component_name, version: cycle_2.version }],
        input_file_path: cycle_2.input_file_path,
        project: project
      )
    end

    let_it_be(:leaf) do
      create(:sbom_occurrence,
        ancestors: [{ name: cycle_3.component_name, version: cycle_3.version }],
        input_file_path: cycle_3.input_file_path,
        project: project
      )
    end

    subject(:service) { described_class.new(project) }

    it "builds expected dependency tree", :aggregate_failures, :freeze_time do
      service.execute
      resulting_paths = Sbom::GraphPath.by_projects(project)
      expect(resulting_paths).to contain_exactly(
        match_path(ancestor.id, cycle_1.id, project.id, 1, service.timestamp, true),
        match_path(cycle_1.id, cycle_2.id, project.id, 1, service.timestamp, false),
        match_path(cycle_2.id, cycle_3.id, project.id, 1, service.timestamp, false),
        match_path(cycle_3.id, cycle_1.id, project.id, 1, service.timestamp, false),
        match_path(cycle_3.id, leaf.id, project.id, 1, service.timestamp, false)
      )
    end
  end

  describe "same package in several input files" do
    let_it_be(:project) { create(:project) }
    let_it_be(:parent) do
      create(:sbom_occurrence, project: project, ancestors: [{}], input_file_path: 'a/Gemfile.lock')
    end

    let_it_be(:other_parent) do
      create(:sbom_occurrence, project: project, ancestors: [{}], input_file_path: 'b/Gemfile.lock',
        component: parent.component, component_version: parent.component_version)
    end

    let_it_be(:child) do
      create(:sbom_occurrence, ancestors: [{ name: parent.component_name, version: parent.version }],
        input_file_path: other_parent.input_file_path, project: project)
    end

    subject(:service) { described_class.new(project) }

    it "links the child to the parent from its own input file", :freeze_time do
      service.execute

      expect(Sbom::GraphPath.by_projects(project)).to contain_exactly(
        match_path(other_parent.id, child.id, project.id, 1, service.timestamp, true)
      )
    end
  end

  describe "duplicate occurrences for the same component and input file" do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:shared_component) { create(:sbom_component) }
    let_it_be(:shared_component_version) { create(:sbom_component_version, component: shared_component) }

    # Monorepos can produce several occurrences of the same component+version under one input file.
    # The parent lookup takes the lowest id, which relies on `sbom_occurrences` being ordered by id.
    let_it_be(:first_parent) do
      create(:sbom_occurrence,
        project: project,
        component: shared_component,
        component_version: shared_component_version,
        input_file_path: 'package.json',
        ancestors: [{}])
    end

    let_it_be(:second_parent) do
      create(:sbom_occurrence,
        project: project,
        component: shared_component,
        component_version: shared_component_version,
        input_file_path: 'package.json',
        ancestors: [{}])
    end

    let_it_be(:child) do
      create(:sbom_occurrence,
        project: project,
        input_file_path: 'package.json',
        ancestors: [{ name: shared_component.name, version: shared_component_version.version }])
    end

    subject(:service) { described_class.new(project) }

    it "resolves the parent to the lowest-id occurrence", :aggregate_failures, :freeze_time do
      expect(first_parent.id).to be < second_parent.id

      service.execute

      expect(Sbom::GraphPath.by_projects(project)).to contain_exactly(
        match_path(first_parent.id, child.id, project.id, 1, service.timestamp, true)
      )
    end
  end
end
