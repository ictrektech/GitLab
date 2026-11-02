# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Factory default associations', feature_category: :tooling do
  row = FactoryDefaults::Row

  it_behaves_like 'factory default associations', [
    row.new(
      factory: :duo_workflows_workflow, skip: :project, passed: { namespace: :group },
      expected: ->(group, _) { { namespace: group, project: nil } }
    ),
    row.new(
      factory: :duo_workflows_checkpoint_write, skip: :project, passed: { workflow: :duo_workflows_workflow },
      expected: ->(workflow, _) { { workflow: workflow, project: workflow.project } }
    ),
    row.new(
      factory: :duo_workflows_checkpoint, skip: :project, passed: { workflow: :duo_workflows_workflow },
      expected: ->(workflow, _) { { workflow: workflow, project: workflow.project } }
    ),
    row.new(
      factory: :virtual_registries_packages_maven_upstream, skip: :group, passed: { group: :group },
      expected: ->(group, _) { { group: group, registries: contain_exactly(have_attributes(group: group)) } }
    ),
    row.new(
      factory: :virtual_registries_container_upstream, skip: :group, passed: { group: :group },
      expected: ->(group, _) { { group: group, registries: contain_exactly(have_attributes(group: group)) } }
    ),
    row.new(
      factory: :virtual_registries_packages_npm_upstream, skip: :group, passed: { group: :group },
      expected: ->(group, _) { { group: group, registries: contain_exactly(have_attributes(group: group)) } }
    ),
    row.new(
      factory: :sbom_occurrence, skip: :project, passed: { project: :project },
      expected: ->(project, _) { { project: project, pipeline: have_attributes(project: project) } }
    ),
    row.new(
      factory: :sbom_occurrence_ref, skip: :project, passed: { project: :project },
      expected: ->(project, _) { { project: project, pipeline: have_attributes(project: project) } }
    )
  ]
end
