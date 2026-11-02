# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::OccurrenceRef, feature_category: :dependency_management do
  describe 'associations' do
    it { is_expected.to belong_to(:project).class_name('Project').inverse_of(:sbom_occurrence_refs) }

    it 'belongs to an occurrence' do
      is_expected.to belong_to(:occurrence)
        .class_name('Sbom::Occurrence')
        .with_foreign_key(:sbom_occurrence_id)
        .inverse_of(:occurrence_refs)
    end

    it 'belongs to a tracked context' do
      is_expected.to belong_to(:tracked_context)
        .class_name('Security::ProjectTrackedContext')
        .with_foreign_key(:security_project_tracked_context_id)
        .inverse_of(:sbom_occurrence_refs)
    end

    it { is_expected.to belong_to(:pipeline).class_name('Ci::Pipeline').inverse_of(:sbom_occurrence_refs).optional }

    describe '#pipeline' do
      it_behaves_like 'a partition-pruned pipeline association' do
        # .reload clears the :pipeline target cached by the attribute writer.
        let(:related_resource) { create(:sbom_occurrence_ref, pipeline: pipeline).reload }
      end
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:commit_sha) }
    it { is_expected.to validate_presence_of(:sbom_occurrence_id) }
    it { is_expected.to validate_presence_of(:security_project_tracked_context_id) }
    it { is_expected.to validate_presence_of(:project_id) }
    it { is_expected.to validate_length_of(:commit_sha).is_at_most(64) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:reachability).with_values(::Enums::Sbom.reachability_types).with_suffix }
  end

  describe 'scopes' do
    describe '.by_occurrence' do
      let_it_be(:occurrence) { create(:sbom_occurrence) }
      let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, occurrence: occurrence) }

      it 'returns occurrence refs for the given occurrence ID' do
        expect(described_class.by_occurrence(occurrence.id)).to include(occurrence_ref)
      end
    end

    describe '.by_tracked_context' do
      let_it_be(:tracked_context) { create(:security_project_tracked_context) }
      let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, tracked_context: tracked_context) }

      it 'returns occurrence refs for the given tracked context ID' do
        expect(described_class.by_tracked_context(tracked_context.id)).to include(occurrence_ref)
      end
    end

    describe '.by_project' do
      let_it_be(:project) { create(:project) }
      let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, project: project) }

      it 'returns occurrence refs for the given project ID' do
        expect(described_class.by_project(project.id)).to include(occurrence_ref)
      end
    end
  end

  describe '.reachability_by_occurrence' do
    let_it_be(:project) { create(:project) }
    let_it_be(:default_context) { create(:security_project_tracked_context, :default, project: project) }
    let_it_be(:feature_context) { create(:security_project_tracked_context, :tracked, project: project) }
    let_it_be(:other_context) { create(:security_project_tracked_context, :tracked, project: project) }

    let_it_be(:on_all_refs) { create(:sbom_occurrence, project: project) }
    let_it_be(:feature_only) { create(:sbom_occurrence, project: project) }

    let(:occurrence_ids) { [on_all_refs.id, feature_only.id] }

    before_all do
      create(:sbom_occurrence_ref, occurrence: on_all_refs, project: project, tracked_context: default_context,
        reachability: :not_found)
      create(:sbom_occurrence_ref, occurrence: on_all_refs, project: project, tracked_context: feature_context,
        reachability: :in_use)
      create(:sbom_occurrence_ref, occurrence: on_all_refs, project: project, tracked_context: other_context,
        reachability: :unknown)
      create(:sbom_occurrence_ref, occurrence: feature_only, project: project, tracked_context: feature_context,
        reachability: :in_use)
    end

    it 'prefers the default branch, falling back to any ref, when unscoped' do
      expect(described_class.reachability_by_occurrence(occurrence_ids))
        .to eq(on_all_refs.id => 'not_found', feature_only.id => 'in_use')
    end

    it 'uses only the default branch for the default_branches scope' do
      expect(described_class.reachability_by_occurrence(occurrence_ids, tracked_refs_scope: :default_branches))
        .to eq(on_all_refs.id => 'not_found')
    end

    it 'uses the strongest value across refs for the all_refs scope' do
      expect(described_class.reachability_by_occurrence(occurrence_ids, tracked_refs_scope: :all_refs))
        .to eq(on_all_refs.id => 'in_use', feature_only.id => 'in_use')
    end

    it 'falls back to the occurrence value for a ref without reachability' do
      unwritten = create(:sbom_occurrence, project: project, reachability: :not_found)
      create(:sbom_occurrence_ref, occurrence: unwritten, project: project, tracked_context: default_context)

      expect(described_class.reachability_by_occurrence([unwritten.id])).to eq(unwritten.id => 'not_found')
    end

    it 'uses only the requested refs, ignoring the scope' do
      result = described_class.reachability_by_occurrence(occurrence_ids,
        tracked_context_ids: [other_context.id], tracked_refs_scope: :default_branches)

      expect(result).to eq(on_all_refs.id => 'unknown')
    end
  end

  describe '.with_pipeline' do
    let_it_be(:pipeline) { create(:ci_pipeline) }
    let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, pipeline: pipeline) }

    it 'associates with the pipeline correctly' do
      expect(occurrence_ref.pipeline).to be_present
    end
  end

  describe 'loose foreign key on sbom_occurrence_refs.pipeline_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let!(:parent) { create(:ci_pipeline) }
      let!(:model) { create(:sbom_occurrence_ref, pipeline: parent) }
    end
  end

  context 'with loose foreign key on sbom_occurrence_refs.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) { create(:sbom_occurrence_ref, project: parent) }
    end
  end
end
