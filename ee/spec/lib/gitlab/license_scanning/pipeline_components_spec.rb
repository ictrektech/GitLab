# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::LicenseScanning::PipelineComponents, feature_category: :software_composition_analysis do
  let_it_be(:project) { create(:project) }

  describe '#fetch' do
    subject(:fetch) { described_class.new(pipeline: pipeline).fetch }

    context 'when the pipeline has an sbom report' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_report_with_license, project: project) }

      context 'and sbom components are not supported by license scanning' do
        let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_container_scanning, project: project) }

        it 'returns an empty list' do
          expect(fetch).to be_empty
        end
      end

      context 'and some of the sbom components do not have purl values' do
        it 'returns a list with the expected size' do
          expected_number_of_components = pipeline.sbom_reports.reports.sum do |report|
            report.components.length - report.components.count { |component| component.purl.blank? }
          end

          expect(fetch.count).to eql(expected_number_of_components)
        end

        it 'returns a list containing the expected elements' do
          expect(fetch).to include(
            { name: "org.codehaus.plexus/plexus-utils", purl_type: "maven", version: "3.0.22", path: nil,
              licenses: [] },
            { name: "org.apache.commons/commons-lang3", purl_type: "maven", version: "3.4", path: nil, licenses: [] },
            { name: "com.example/util/library", purl_type: "maven", version: "2.0.0", path: nil, licenses: [
              an_object_having_attributes(name: "Example, Inc. Commercial License", spdx_identifier: nil, url: nil)
            ] }
          )
        end
      end
    end

    context 'when the pipeline does not have an sbom report' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_dependency_scanning_report, project: project) }

      it 'returns an empty list' do
        expect(fetch).to be_empty
      end
    end

    context 'when the pipeline does not have any reports' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, project: project) }

      it 'returns an empty list' do
        expect(fetch).to be_empty
      end
    end
  end

  # The user argument decides whether artifact reads are authorization-scoped.
  # Regression coverage for gitlab-org/gitlab#597328.
  describe 'artifact scoping by user' do
    let_it_be(:project) { create(:project, :private) }
    let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }
    let_it_be(:reporter) { create(:user, reporter_of: project) }
    let_it_be(:maintainer) { create(:user, maintainer_of: project) }

    before_all do
      create(:ee_ci_job_artifact, :cyclonedx, :maintainer_only_access,
        job: create(:ci_build, :success, name: 'cyclonedx', pipeline: pipeline))
    end

    def fetch_for(user)
      described_class.new(pipeline: pipeline, user: user).fetch
    end

    it 'reads every artifact for the unscoped sentinel, which is the default' do
      expect(described_class.new(pipeline: pipeline).fetch).to be_present
      expect(fetch_for(::Gitlab::LicenseScanning::UNSCOPED)).to be_present
    end

    it 'includes maintainer-only content for a user who can read it' do
      expect(fetch_for(maintainer)).to be_present
    end

    it 'excludes maintainer-only content from a reporter' do
      expect(fetch_for(reporter)).to be_empty
    end

    it 'treats a nil (guest) user as unable to read restricted content' do
      expect(fetch_for(nil)).to be_empty
    end

    it 'routes an unscoped read to the unfiltered pipeline reports' do
      expect(pipeline).to receive(:sbom_reports).and_call_original
      expect(pipeline).not_to receive(:accessible_sbom_reports)

      described_class.new(pipeline: pipeline).fetch
    end

    it 'routes a user read through the authorization-filtered reports' do
      expect(pipeline).to receive(:accessible_sbom_reports).with(reporter).and_call_original

      fetch_for(reporter)
    end
  end
end
