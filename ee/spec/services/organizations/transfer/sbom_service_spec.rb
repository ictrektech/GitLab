# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::SbomService, :aggregate_failures, feature_category: :dependency_management do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: old_organization) }
  let_it_be(:subgroup) { create(:group, parent: group, organization: old_organization) }
  let_it_be(:project) { create(:project, namespace: group, organization: old_organization) }
  let_it_be(:subgroup_project) { create(:project, namespace: subgroup, organization: old_organization) }

  let(:service) do
    described_class.new(
      group: group,
      old_organization: old_organization,
      new_organization: new_organization
    )
  end

  describe '#execute' do
    it_behaves_like 'an organization transfer service handling missing records'

    context 'with an occurrence in the root group' do
      let_it_be(:component) { create(:sbom_component, organization: old_organization) }
      let_it_be(:component_version) do
        create(:sbom_component_version, component: component, organization: old_organization)
      end

      let_it_be(:source_package) { create(:sbom_source_package, organization: old_organization) }
      let_it_be(:source) { create(:sbom_source, organization: old_organization) }
      let_it_be_with_refind(:occurrence) do
        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component,
          component_version: component_version,
          source_package: source_package,
          source: source
        )
      end

      it 'duplicates the lookup records and repoints every foreign key' do
        service.execute

        occurrence.reload
        new_component = occurrence.component
        new_component_version = occurrence.component_version
        new_source_package = occurrence.source_package
        new_source = occurrence.source

        expect(new_component.organization_id).to eq(new_organization.id)
        expect(new_component_version.organization_id).to eq(new_organization.id)
        expect(new_component_version.component_id).to eq(new_component.id)
        expect(new_source_package.organization_id).to eq(new_organization.id)
        expect(new_source.organization_id).to eq(new_organization.id)
        expect(new_component.id).not_to eq(component.id)
        expect(new_component_version.id).not_to eq(component_version.id)
        expect(new_source_package.id).not_to eq(source_package.id)
        expect(new_source.id).not_to eq(source.id)
      end

      it 'reuses matching lookup records in the target organization' do
        target_component = create(
          :sbom_component,
          organization: new_organization,
          name: component.name,
          purl_type: component.purl_type,
          component_type: component.component_type
        )
        target_component_version = create(
          :sbom_component_version,
          organization: new_organization,
          component: target_component,
          version: component_version.version
        )
        target_source_package = create(
          :sbom_source_package,
          organization: new_organization,
          name: source_package.name,
          purl_type: source_package.purl_type
        )
        target_source = create(
          :sbom_source,
          organization: new_organization,
          source_type: source.source_type,
          source: source.source
        )

        expect { service.execute }.not_to change {
          [
            Sbom::Component.count,
            Sbom::ComponentVersion.count,
            Sbom::SourcePackage.count,
            Sbom::Source.count
          ]
        }

        expect(occurrence.reload).to have_attributes(
          component_id: target_component.id,
          component_version_id: target_component_version.id,
          source_package_id: target_source_package.id,
          source_id: target_source.id
        )
      end

      it 'is idempotent' do
        service.execute
        transferred_ids = occurrence.reload.attributes.slice(
          'component_id',
          'component_version_id',
          'source_package_id',
          'source_id'
        )

        expect { service.execute }.not_to change {
          [
            Sbom::Component.count,
            Sbom::ComponentVersion.count,
            Sbom::SourcePackage.count,
            Sbom::Source.count
          ]
        }

        expect(occurrence.reload.attributes).to include(transferred_ids)
      end

      it 'preserves nil optional foreign keys' do
        occurrence.update_columns(component_version_id: nil, source_package_id: nil, source_id: nil)

        service.execute

        expect(occurrence.reload).to have_attributes(
          component_version_id: nil,
          source_package_id: nil,
          source_id: nil
        )
        expect(occurrence.component.organization_id).to eq(new_organization.id)
      end
    end

    context 'with an occurrence in a subgroup' do
      let_it_be_with_refind(:occurrence) do
        component = create(:sbom_component, organization: old_organization)
        component_version = create(:sbom_component_version, component: component, organization: old_organization)

        create(
          :sbom_occurrence,
          project: subgroup_project,
          pipeline: create(:ci_pipeline, project: subgroup_project),
          component: component,
          component_version: component_version,
          source_package: create(:sbom_source_package, organization: old_organization),
          source: create(:sbom_source, organization: old_organization)
        )
      end

      it 'repoints the occurrence to lookup records in the target organization' do
        service.execute

        expect(occurrence.reload.component.organization_id).to eq(new_organization.id)
        expect(occurrence.component_version.organization_id).to eq(new_organization.id)
        expect(occurrence.source_package.organization_id).to eq(new_organization.id)
        expect(occurrence.source.organization_id).to eq(new_organization.id)
      end
    end

    context 'when lookup records are shared with a project outside the group' do
      let_it_be(:outside_group) { create(:group, organization: old_organization) }
      let_it_be(:outside_project) { create(:project, namespace: outside_group, organization: old_organization) }
      let_it_be(:component) { create(:sbom_component, organization: old_organization) }
      let_it_be(:component_version) do
        create(:sbom_component_version, component: component, organization: old_organization)
      end

      let_it_be(:source_package) { create(:sbom_source_package, organization: old_organization) }
      let_it_be(:source) { create(:sbom_source, organization: old_organization) }
      let_it_be_with_refind(:inside_occurrence) do
        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component,
          component_version: component_version,
          source_package: source_package,
          source: source
        )
      end

      let_it_be_with_refind(:outside_occurrence) do
        create(
          :sbom_occurrence,
          project: outside_project,
          pipeline: create(:ci_pipeline, project: outside_project),
          component: component,
          component_version: component_version,
          source_package: source_package,
          source: source
        )
      end

      it 'repoints only the occurrence inside the transferred hierarchy' do
        service.execute

        expect(inside_occurrence.reload.component.organization_id).to eq(new_organization.id)
        expect(outside_occurrence.reload).to have_attributes(
          component_id: component.id,
          component_version_id: component_version.id,
          source_package_id: source_package.id,
          source_id: source.id
        )
        expect(component.reload.organization_id).to eq(old_organization.id)
        expect(component_version.reload.organization_id).to eq(old_organization.id)
        expect(source_package.reload.organization_id).to eq(old_organization.id)
        expect(source.reload.organization_id).to eq(old_organization.id)
      end
    end

    context 'when two components share the same version string' do
      let_it_be(:component_a) { create(:sbom_component, organization: old_organization) }
      let_it_be(:component_b) { create(:sbom_component, organization: old_organization) }
      let_it_be(:version_a) do
        create(:sbom_component_version, component: component_a, version: '1.0.0', organization: old_organization)
      end

      let_it_be(:version_b) do
        create(:sbom_component_version, component: component_b, version: '1.0.0', organization: old_organization)
      end

      let_it_be_with_refind(:occurrence_a) do
        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component_a,
          component_version: version_a,
          source_package: create(:sbom_source_package, organization: old_organization),
          source: create(:sbom_source, organization: old_organization)
        )
      end

      let_it_be_with_refind(:occurrence_b) do
        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component_b,
          component_version: version_b,
          source_package: create(:sbom_source_package, organization: old_organization),
          source: create(:sbom_source, organization: old_organization)
        )
      end

      it 'maps each occurrence to the correct component version in the target organization' do
        service.execute

        occurrence_a.reload
        occurrence_b.reload

        expect(occurrence_a.component_version.component_id).to eq(occurrence_a.component_id)
        expect(occurrence_b.component_version.component_id).to eq(occurrence_b.component_id)
        expect(occurrence_a.component_id).not_to eq(occurrence_b.component_id)
      end
    end

    context 'when an occurrence belongs to an unrelated organization' do
      let_it_be(:unrelated_organization) { create(:organization) }
      let_it_be(:unrelated_group) { create(:group, organization: unrelated_organization) }
      let_it_be(:unrelated_project) do
        create(:project, namespace: unrelated_group, organization: unrelated_organization)
      end

      let_it_be_with_refind(:unrelated_occurrence) do
        component = create(:sbom_component, organization: unrelated_organization)
        component_version = create(
          :sbom_component_version,
          component: component,
          organization: unrelated_organization
        )

        create(
          :sbom_occurrence,
          project: unrelated_project,
          pipeline: create(:ci_pipeline, project: unrelated_project),
          component: component,
          component_version: component_version,
          source_package: create(:sbom_source_package, organization: unrelated_organization),
          source: create(:sbom_source, organization: unrelated_organization)
        )
      end

      it 'does not modify the occurrence' do
        original_ids = unrelated_occurrence.attributes.slice(
          'component_id',
          'component_version_id',
          'source_package_id',
          'source_id'
        )

        service.execute

        expect(unrelated_occurrence.reload.attributes).to include(original_ids)
      end
    end

    context 'when batching transfers' do
      include_context 'with transfer batch size of 1'

      let_it_be_with_refind(:occurrences) do
        Array.new(3) do
          component = create(:sbom_component, organization: old_organization)
          component_version = create(:sbom_component_version, component: component, organization: old_organization)

          create(
            :sbom_occurrence,
            project: project,
            pipeline: create(:ci_pipeline, project: project),
            component: component,
            component_version: component_version,
            source_package: create(:sbom_source_package, organization: old_organization),
            source: create(:sbom_source, organization: old_organization)
          )
        end
      end

      let(:execute_service) { service.execute }
      let(:expected_batch_queries) { { 'sbom_occurrences' => 3 } }
      let(:expected_upsert_queries) do
        {
          'sbom_components' => 3,
          'sbom_component_versions' => 3,
          'sbom_source_packages' => 3,
          'sbom_sources' => 3
        }
      end

      it 'processes all lookup records across multiple batches' do
        service.execute

        occurrences.each do |occurrence|
          occurrence.reload

          expect(occurrence.component.organization_id).to eq(new_organization.id)
          expect(occurrence.component_version.organization_id).to eq(new_organization.id)
          expect(occurrence.source_package.organization_id).to eq(new_organization.id)
          expect(occurrence.source.organization_id).to eq(new_organization.id)
        end
      end

      it_behaves_like 'generates batched transfer queries'
      it_behaves_like 'generates batched upsert queries'
    end

    context 'when a required lookup mapping cannot be resolved' do
      include_context 'with transfer batch size of 1'

      let_it_be(:unrelated_organization) { create(:organization) }
      let_it_be_with_refind(:valid_occurrence) do
        component = create(:sbom_component, organization: old_organization)
        component_version = create(:sbom_component_version, component: component, organization: old_organization)

        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component,
          component_version: component_version,
          source_package: create(:sbom_source_package, organization: old_organization),
          source: create(:sbom_source, organization: old_organization)
        )
      end

      let_it_be_with_refind(:occurrence) do
        component = create(:sbom_component, organization: unrelated_organization)
        component_version = create(
          :sbom_component_version,
          component: component,
          organization: unrelated_organization
        )

        create(
          :sbom_occurrence,
          project: project,
          pipeline: create(:ci_pipeline, project: project),
          component: component,
          component_version: component_version,
          source_package: create(:sbom_source_package, organization: old_organization),
          source: create(:sbom_source, organization: old_organization)
        )
      end

      it 'raises and rolls back only the failing batch' do
        original_ids = occurrence.attributes.slice(
          'component_id',
          'component_version_id',
          'source_package_id',
          'source_id'
        )

        expect { service.execute }.to raise_error(KeyError)

        expect(valid_occurrence.reload.component.organization_id).to eq(new_organization.id)
        expect(occurrence.reload.attributes).to include(original_ids)
        expect(Sbom::Component.where(organization: new_organization).count).to eq(1)
        expect(Sbom::ComponentVersion.where(organization: new_organization).count).to eq(1)
        expect(Sbom::SourcePackage.where(organization: new_organization).count).to eq(1)
        expect(Sbom::Source.where(organization: new_organization).count).to eq(1)
      end
    end
  end
end
