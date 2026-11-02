# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::References::Sbom::OccurrenceRef, :elastic_helpers, :request_store,
  feature_category: :dependency_management do
  let_it_be(:parent_group) { create(:group) }
  let_it_be(:group) { create(:group, parent: parent_group) }
  let_it_be(:project) { create(:project, group: group) }

  let_it_be_with_reload(:occurrence) do
    create(:sbom_occurrence, :mit, project: project, vulnerability_count: 3)
  end

  let_it_be_with_reload(:occurrence_ref) do
    create(:sbom_occurrence_ref, project: project, occurrence: occurrence)
  end

  let(:reference) { described_class.new(occurrence_ref.id, occurrence_ref.es_parent) }

  before do
    allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?).and_return(true)
  end

  describe '#as_indexed_json', :freeze_time do
    let(:tracked_context) { occurrence_ref.tracked_context }
    let(:component) { occurrence.component }
    let(:component_version) { occurrence.component_version }
    let(:source) { occurrence.source }
    let(:primary_license) { occurrence.licenses.first }

    let(:expected_hash) do
      {
        type: described_class::DOC_TYPE,
        schema_version: described_class::SCHEMA_VERSION,
        project_id: occurrence_ref.project_id,
        sbom_occurrence_id: occurrence_ref.sbom_occurrence_id,
        security_project_tracked_context_id: occurrence_ref.security_project_tracked_context_id,
        pipeline_id: occurrence_ref.pipeline_id,
        commit_sha: occurrence_ref.commit_sha,
        is_default: tracked_context.is_default,
        traversal_ids: project.namespace.elastic_namespace_ancestry,
        component_name: occurrence.component_name,
        component_version: component_version.version,
        component_id: occurrence.component_id,
        component_version_id: occurrence.component_version_id,
        source_id: occurrence.source_id,
        source_type: source.source_type_before_type_cast,
        package_manager: occurrence.package_manager,
        input_file_path: occurrence.input_file_path,
        primary_license_spdx_identifier: primary_license['spdx_identifier'],
        primary_license_name: primary_license['name'],
        secondary_license_spdx_identifier: nil,
        secondary_license_name: nil,
        highest_severity: occurrence.highest_severity_before_type_cast,
        vulnerability_count: occurrence.vulnerability_count,
        reachability: occurrence.reachability_before_type_cast,
        archived: occurrence.archived,
        uuid: occurrence.uuid,
        purl_type: component.purl_type_before_type_cast,
        component_type: component.component_type_before_type_cast,
        source_package_name: component_version.source_package_name,
        created_at: be_within(0.1.seconds).of(occurrence.created_at),
        updated_at: be_within(0.1.seconds).of(occurrence.updated_at),
        malware: occurrence.malware_status,
        policy_violations: ::Security::PolicyViolations::NOT_APPLICABLE
      }
    end

    # PRELOADED_FIELDS are read off the proxy .preload_indexing_data assigns, which
    # Elastic::ProcessBookkeepingService always runs first.
    subject(:indexed_json) do
      described_class.preload_indexing_data([reference])
      reference.as_indexed_json.with_indifferent_access
    end

    it 'serializes the occurrence ref as a hash' do
      expect(indexed_json).to match(expected_hash)
    end

    describe 'reachability' do
      before do
        occurrence.update!(reachability: :not_found)
      end

      it 'falls back to the occurrence when the ref has no reachability yet' do
        expect(indexed_json[:reachability]).to eq(::Enums::Sbom.reachability_types[:not_found])
      end

      it 'uses the ref when it has a reachability' do
        occurrence_ref.update!(reachability: :in_use)

        expect(indexed_json[:reachability]).to eq(::Enums::Sbom.reachability_types[:in_use])
      end
    end

    describe 'policy_violations' do
      context 'when the mapping migration has not completed' do
        before do
          set_elasticsearch_migration_to(:add_policy_violations_to_sbom_occurrence_refs, including: false)
        end

        # The mapping is dynamic: 'strict', so the key has to be absent rather than null --
        # Elasticsearch would otherwise reject the whole document.
        it 'omits the field entirely' do
          expect(indexed_json).not_to have_key('policy_violations')
        end

        it 'stamps the previous schema version' do
          expect(indexed_json[:schema_version]).to eq(26_01)
        end
      end

      it 'stamps the schema version that introduced the field' do
        expect(indexed_json[:schema_version]).to eq(26_02)
      end
    end

    context 'with multiple licenses including a non-SPDX one' do
      let(:multi_license_occurrence) do
        create(:sbom_occurrence, :mit, :license_without_spdx_id, project: project)
      end

      let(:multi_license_ref) do
        create(:sbom_occurrence_ref, project: project, occurrence: multi_license_occurrence)
      end

      let(:reference) { described_class.new(multi_license_ref.id, multi_license_ref.es_parent) }

      it 'denormalises primary from licenses[0] and secondary from licenses[1]', :aggregate_failures do
        expect(indexed_json[:primary_license_spdx_identifier]).to eq('MIT')
        expect(indexed_json[:secondary_license_spdx_identifier]).to be_nil
        expect(indexed_json[:secondary_license_name]).to eq('Custom License')
      end
    end

    context 'when the occurrence has no licenses' do
      let(:no_license_occurrence) { create(:sbom_occurrence, project: project) }
      let(:no_license_ref) do
        create(:sbom_occurrence_ref, project: project, occurrence: no_license_occurrence)
      end

      let(:reference) { described_class.new(no_license_ref.id, no_license_ref.es_parent) }

      it 'returns nil primary and secondary license fields', :aggregate_failures do
        expect(indexed_json[:primary_license_spdx_identifier]).to be_nil
        expect(indexed_json[:primary_license_name]).to be_nil
        expect(indexed_json[:secondary_license_spdx_identifier]).to be_nil
        expect(indexed_json[:secondary_license_name]).to be_nil
      end
    end

    context 'when the project has been deleted' do
      before do
        reference.database_record = occurrence_ref
        allow(occurrence_ref).to receive(:project).and_return(nil)
      end

      it 'raises DocumentShouldBeDeletedFromIndexError' do
        expect { reference.as_indexed_json }
          .to raise_error(::Elastic::Latest::DocumentShouldBeDeletedFromIndexError)
      end
    end

    # The indexing path assigns a proxy, and SimpleDelegator does not delegate #class.
    context 'when the project has been deleted and the record was preloaded' do
      let(:proxy) do
        ::Search::Elastic::RecordProxy::SbomOccurrenceRef.create_with_enhancements(occurrence_ref, {})
      end

      before do
        reference.database_record = proxy
        allow(occurrence_ref).to receive(:project).and_return(nil)
      end

      it 'reports the model class rather than the proxy class' do
        expect { reference.as_indexed_json }
          .to raise_error(::Elastic::Latest::DocumentShouldBeDeletedFromIndexError) do |error|
            expect(error.class_name).to eq('Sbom::OccurrenceRef')
          end
      end
    end
  end

  describe '.preload_indexing_data' do
    let_it_be(:other_project) { create(:project, group: group) }
    let_it_be(:third_project) { create(:project, group: group) }

    def build_ref(ref_project)
      ref_occurrence = create(:sbom_occurrence, :mit, project: ref_project)
      vulnerability = SecApplicationRecord.feature_flagged_transaction_for(ref_project) do
        create(:vulnerability, :with_finding, project: ref_project).tap do |vuln|
          create(:vulnerability_read, :with_identifer_name, vulnerability: vuln, project: ref_project,
            identifier_names: ['GLAM-malicious-package'])
        end
      end
      create(:sbom_occurrences_vulnerability, occurrence: ref_occurrence, vulnerability: vulnerability)

      ref_record = create(:sbom_occurrence_ref, project: ref_project, occurrence: ref_occurrence)
      described_class.new(ref_record.id, ref_record.es_parent)
    end

    it 'preloads the database records onto the references' do
      ref = build_ref(project)

      expect(::Sbom::OccurrenceRef).to receive(:preload_indexing_data).and_call_original

      described_class.preload_indexing_data([ref])

      expect(ref.database_record).to be_present
    end

    context 'with policy_violations data' do
      let_it_be(:dismissed_record) { create(:sbom_occurrence_ref, project: project) }
      let_it_be(:undismissed_record) { create(:sbom_occurrence_ref, project: other_project) }

      let_it_be(:dismissal) do
        create(:policy_dismissal, :preserved, project: project,
          license_occurrence_uuids: [dismissed_record.occurrence.uuid])
      end

      it 'preloads policy_violations' do
        refs = [dismissed_record, undismissed_record].map do |record|
          described_class.new(record.id, record.es_parent)
        end

        described_class.preload_indexing_data(refs)

        expect(refs.first.as_indexed_json[:policy_violations]).to eq(::Security::PolicyViolations::DISMISSED_IN_MR)
        expect(refs.last.as_indexed_json[:policy_violations]).to eq(::Security::PolicyViolations::NOT_APPLICABLE)
      end
    end

    context 'with malware data' do
      let_it_be(:malicious_component) { create(:sbom_component, name: 'malicious-pkg', purl_type: 'npm') }
      let_it_be(:malicious_version) do
        create(:sbom_component_version, component: malicious_component, version: '1.0.0')
      end

      let_it_be(:affected_package) do
        create(:pm_malware_affected_package, purl_type: 'npm', package_name: 'malicious-pkg',
          affected_range: '=1.0.0')
      end

      let_it_be(:malicious_record) do
        malicious_occurrence = create(:sbom_occurrence, project: project, component: malicious_component,
          component_version: malicious_version)

        create(:sbom_occurrence_ref, project: project, occurrence: malicious_occurrence)
      end

      it 'preloads malware' do
        refs = [malicious_record, occurrence_ref].map do |record|
          described_class.new(record.id, record.es_parent)
        end

        described_class.preload_indexing_data(refs)

        expect(refs.first.as_indexed_json[:malware]).to be(true)
        expect(refs.last.as_indexed_json[:malware]).to be(false)
      end

      # malware's default is resolved from the record, so a failed batch must not index it clean.
      it 'resolves malware from the occurrence when the batch lookup failed' do
        ref = described_class.new(malicious_record.id, malicious_record.es_parent)

        allow_next_instance_of(::Search::Elastic::Preloaders::SbomOccurrenceRef::Malware) do |instance|
          allow(instance).to receive(:perform_preload).and_raise(StandardError, 'Database error')
        end
        allow(::Gitlab::ErrorTracking).to receive(:track_exception)

        described_class.preload_indexing_data([ref])

        expect(ref.as_indexed_json[:malware]).to be(true)
      end
    end

    context 'for database_record' do
      it 'without preloading returns an instance of the model class' do
        expect(reference.database_record).to be_an_instance_of(described_class.model_klass)
      end

      it 'with preloading it returns the proxy record' do
        described_class.preload_indexing_data([reference])

        expect(reference.database_record).to be_an_instance_of(::Search::Elastic::RecordProxy::SbomOccurrenceRef)
      end

      # Both fields are scalar mappings, so a record that skipped preloading has to fall back to a
      # value a term filter can match rather than to an empty array.
      it 'resolves both fields when the record skipped preloading' do
        expect(reference.as_indexed_json).to include(
          policy_violations: ::Security::PolicyViolations::NOT_APPLICABLE,
          malware: false
        )
      end
    end

    it 'does not have N+1 queries when serializing multiple references' do
      control_refs = [build_ref(project)]

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        described_class.preload_indexing_data(control_refs)
        control_refs.each(&:as_indexed_json)
      end

      refs = [
        build_ref(project),
        build_ref(other_project),
        build_ref(third_project)
      ]

      expect do
        described_class.preload_indexing_data(refs)
        refs.each(&:as_indexed_json)
      end.not_to exceed_all_query_limit(control)
    end
  end

  describe '.serialize' do
    it 'returns serialized string from class method' do
      expect(described_class.serialize(occurrence_ref))
        .to eq("Sbom::OccurrenceRef|#{occurrence_ref.id}|#{occurrence_ref.es_parent}")
    end
  end

  describe '#serialize' do
    it 'returns serialized string from instance method' do
      expect(reference.serialize)
        .to eq("Sbom::OccurrenceRef|#{occurrence_ref.id}|#{occurrence_ref.es_parent}")
    end
  end

  describe '.instantiate' do
    it 'instantiates from a serialized string' do
      new_ref = described_class.instantiate(reference.serialize)

      expect(new_ref.identifier).to eq(occurrence_ref.id)
      expect(new_ref.routing).to eq(occurrence_ref.es_parent)
    end
  end

  describe '#klass' do
    it 'returns the full namespaced class name' do
      expect(reference.klass).to eq('Sbom::OccurrenceRef')
    end
  end

  describe '#index_name' do
    it 'returns correct environment based index name from class method' do
      expect(described_class.index).to eq('gitlab-test-sbom_occurrence_refs')
    end

    it 'returns correct environment based index name from instance method' do
      expect(reference.index_name).to eq('gitlab-test-sbom_occurrence_refs')
    end
  end

  describe '.model_klass' do
    it 'returns Sbom::OccurrenceRef' do
      expect(described_class.model_klass).to eq(::Sbom::OccurrenceRef)
    end
  end

  describe '#operation' do
    context 'when the database record exists' do
      it 'returns :index' do
        expect(reference.operation).to eq(:index)
      end
    end

    context 'when the database record does not exist' do
      it 'returns :delete' do
        ref = described_class.new(non_existing_record_id, 'group_1')

        expect(ref.operation).to eq(:delete)
      end
    end
  end
end
