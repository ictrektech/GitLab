# frozen_string_literal: true

require 'spec_helper'

# Regression test for security issue gitlab-org/gitlab#597328.
# The MR license_scanning_reports endpoint reads base+head sbom (CycloneDX)
# artifacts via SCA::LicenseCompliance -> SbomScanner -> PipelineComponents ->
# Pipeline#sbom_reports, gated only by project-level :read_licenses (which a
# Reporter has), never per artifact. The user-aware #accessible_sbom_reports must
# exclude sbom artifacts the viewer cannot read, so a Reporter cannot read the
# content of a maintainer-only artifact. The unscoped #sbom_reports stays intact
# for internal callers (ingestion, approval checks) that run without a user.
RSpec.describe Ci::Pipeline, feature_category: :software_composition_analysis do
  let_it_be(:project) { create(:project, :private) }
  let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }

  before_all do
    create(:ee_ci_job_artifact, :cyclonedx, :maintainer_only_access,
      job: create(:ci_build, :success, name: 'cyclonedx', pipeline: pipeline))
  end

  describe '#accessible_sbom_reports' do
    it 'excludes maintainer-only content from a reporter' do
      expect(pipeline.accessible_sbom_reports(reporter).reports).to be_empty
    end

    it 'includes it for a user who can read maintainer artifacts' do
      expect(pipeline.accessible_sbom_reports(maintainer).reports).to be_present
    end

    it 'treats a nil (anonymous) user as unable to read restricted content' do
      expect(pipeline.accessible_sbom_reports(nil).reports).to be_empty
    end
  end

  it 'still returns everything via the unscoped #sbom_reports' do
    expect(pipeline.sbom_reports.reports).to be_present
  end

  context 'when a maintainer-only report is on a descendant (child) pipeline' do
    let_it_be(:child_pipeline) { create(:ci_pipeline, :success, child_of: pipeline) }

    before_all do
      create(:ee_ci_job_artifact, :cyclonedx, :maintainer_only_access,
        job: create(:ci_build, :success, name: 'cyclonedx-child', pipeline: child_pipeline))
    end

    describe '#accessible_sbom_reports with self_and_project_descendants' do
      it 'excludes maintainer-only content from a reporter' do
        expect(pipeline.accessible_sbom_reports(reporter, self_and_project_descendants: true).reports).to be_empty
      end

      it 'adds the child report for a user who can read maintainer artifacts' do
        parent_only = pipeline.accessible_sbom_reports(maintainer).reports.count
        with_children = pipeline.accessible_sbom_reports(maintainer, self_and_project_descendants: true).reports.count

        expect(with_children).to be > parent_only
      end
    end
  end
end
