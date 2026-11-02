# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::CreateOccurrencesVulnerabilitiesService, feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:project_2) { create(:project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
  let_it_be(:vulnerability_2) { create(:vulnerability, :with_finding, project: project_2) }
  let_it_be(:vulnerability_unused) { create(:vulnerability, :with_finding, project: project) }
  let_it_be(:occurrence) { create(:sbom_occurrence, project: project) }
  let_it_be(:occurrence_2) do
    create(:sbom_occurrence, project: project_2, component: create(:sbom_component, name: "bundler"))
  end

  let_it_be(:occurrence_unused) { create(:sbom_occurrence, project: project, component_name: "unused") }

  let(:findings) do
    [
      {
        uuid: vulnerability.finding.uuid,
        project_id: project.id,
        vulnerability_id: vulnerability.id,
        package_name: occurrence.component_name,
        package_version: occurrence.version,
        purl_type: occurrence.purl_type
      }
    ]
  end

  describe '.execute' do
    it 'calls execute on a instance level' do
      expect(described_class).to receive_message_chain(:new, :execute)

      described_class.execute(findings)
    end
  end

  describe '#execute' do
    subject(:service_execute) { described_class.new(findings).execute }

    it 'creates DB entries based on vulnerability and occurrence data' do
      expect { service_execute }.to change { Sbom::OccurrencesVulnerability.count }.by(findings.count)

      expect(Sbom::OccurrencesVulnerability.all).to include(
        have_attributes(sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability.id)
      )
    end

    it 'sets vulnerability_occurrence_id from vulnerabilities.finding_id' do
      service_execute

      record = Sbom::OccurrencesVulnerability.find_by(sbom_occurrence_id: occurrence.id, vulnerability: vulnerability)

      expect(record.vulnerability_occurrence_id).to eq(vulnerability.finding_id)
    end

    context 'with an existing record without vulnerability_occurrence_id' do
      let!(:existing_record) do
        create(:sbom_occurrences_vulnerability, occurrence: occurrence, vulnerability: vulnerability,
          updated_at: 1.day.ago)
      end

      it 'does not update the existing record' do
        expect { service_execute }.not_to change { existing_record.reload.attributes }
      end
    end

    context 'with no related records' do
      let(:findings) do
        [
          {
            uuid: "uuid",
            project_id: 0,
            vulnerability_id: 0,
            package_name: "package_name",
            package_version: "0",
            purl_type: "purl_type"
          }
        ]
      end

      it 'does not create DB entries based on vulnerability and occurrence data' do
        expect { service_execute }.not_to change { Sbom::OccurrencesVulnerability.count }
      end
    end

    context 'with different purl_type' do
      let(:findings) do
        [
          {
            uuid: vulnerability.finding.uuid,
            project_id: project.id,
            vulnerability_id: vulnerability.id,
            package_name: occurrence.component_name,
            package_version: occurrence.version,
            purl_type: 'pypi'
          }
        ]
      end

      it 'does not create DB entries based on vulnerability and occurrence data' do
        expect { service_execute }.not_to change { Sbom::OccurrencesVulnerability.count }
      end
    end

    context 'when component_name on the occurrence is NULL' do
      let(:findings) do
        [
          {
            uuid: vulnerability.finding.uuid,
            project_id: project.id,
            vulnerability_id: vulnerability.id,
            package_name: occurrence.component.name,
            package_version: occurrence.version,
            purl_type: occurrence.purl_type
          }
        ]
      end

      before do
        Sbom::Occurrence.id_in(occurrence.id).update_all(component_name: nil)
      end

      it 'finds the occurrence by the component name' do
        expect { service_execute }.to change { Sbom::OccurrencesVulnerability.count }.by(1)
      end
    end

    context 'with multiple vulnerabilities related to a single occurrence' do
      let(:findings) do
        [
          {
            uuid: vulnerability.finding.uuid,
            project_id: project.id,
            vulnerability_id: vulnerability.id,
            package_name: occurrence.component_name,
            package_version: occurrence.version,
            purl_type: occurrence.purl_type
          },
          {
            uuid: vulnerability_2.finding.uuid,
            project_id: project.id,
            vulnerability_id: vulnerability_2.id,
            package_name: occurrence.component_name,
            package_version: occurrence.version,
            purl_type: occurrence.purl_type
          }
        ]
      end

      it 'creates DB entries based on vulnerability and occurrence data' do
        expect { service_execute }.to change { Sbom::OccurrencesVulnerability.count }.by(findings.count)

        expect(Sbom::OccurrencesVulnerability.all).to include(
          have_attributes(sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability.id),
          have_attributes(sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability_2.id)
        )
      end
    end

    context 'with multiple occurrences related to a single vulnerability' do
      let(:findings) do
        [
          {
            uuid: vulnerability.finding.uuid,
            project_id: project.id,
            vulnerability_id: vulnerability.id,
            package_name: occurrence.component_name,
            package_version: occurrence.version,
            purl_type: occurrence.purl_type
          },
          {
            uuid: vulnerability.finding.uuid,
            project_id: project_2.id,
            vulnerability_id: vulnerability.id,
            package_name: occurrence_2.component_name,
            package_version: occurrence_2.version,
            purl_type: occurrence_2.purl_type
          }
        ]
      end

      it 'creates DB entries based on vulnerability and occurrence data' do
        expect { service_execute }.to change { Sbom::OccurrencesVulnerability.count }.by(findings.count)

        expect(Sbom::OccurrencesVulnerability.all).to include(
          have_attributes(sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability.id),
          have_attributes(sbom_occurrence_id: occurrence_2.id, vulnerability_id: vulnerability.id)
        )
      end

      context 'with an existing record in relation to vulnerability and occurrence ids' do
        before do
          create(:sbom_occurrences_vulnerability, sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability.id)
        end

        it 'creates only unique DB entries based on vulnerability and occurrence data' do
          expect { service_execute }.to change { Sbom::OccurrencesVulnerability.count }.by(findings.count - 1)

          expect(Sbom::OccurrencesVulnerability.all).to include(
            have_attributes(sbom_occurrence_id: occurrence.id, vulnerability_id: vulnerability.id),
            have_attributes(sbom_occurrence_id: occurrence_2.id, vulnerability_id: vulnerability.id)
          )
        end
      end
    end

    describe 'Elasticsearch synchronization' do
      context 'with single vulnerability' do
        # Uses the default findings from the outer scope
        it_behaves_like 'it syncs vulnerabilities with ES', -> { [vulnerability.id] }, :service_execute
      end

      context 'with no related records' do
        let(:findings) do
          [
            {
              uuid: "uuid",
              project_id: 0,
              vulnerability_id: 0,
              package_name: "package_name",
              package_version: "0",
              purl_type: "purl_type"
            }
          ]
        end

        it_behaves_like 'does not sync with ES when no vulnerabilities', :service_execute
      end

      context 'with multiple vulnerabilities' do
        let(:findings) do
          [
            {
              uuid: vulnerability.finding.uuid,
              project_id: project.id,
              vulnerability_id: vulnerability.id,
              package_name: occurrence.component_name,
              package_version: occurrence.version,
              purl_type: occurrence.purl_type
            },
            {
              uuid: vulnerability_2.finding.uuid,
              project_id: project.id,
              vulnerability_id: vulnerability_2.id,
              package_name: occurrence.component_name,
              package_version: occurrence.version,
              purl_type: occurrence.purl_type
            }
          ]
        end

        it_behaves_like 'it syncs vulnerabilities with ES',
          -> { [vulnerability.id, vulnerability_2.id] }, :service_execute
      end
    end
  end
end
