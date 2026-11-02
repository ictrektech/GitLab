# frozen_string_literal: true

require 'spec_helper'

# Regression test for security issue gitlab-org/gitlab#597328.
# The EE MR metrics_reports endpoint reads base+head reports but authorizes
# read_pipeline on the HEAD pipeline only. #accessible_metrics_reports must
# exclude artifacts the viewer cannot read, mirroring the accessibility and
# codequality paths hardened under the same issue.
RSpec.describe Ci::Pipeline, feature_category: :observability do
  let_it_be(:project) { create(:project, :private) }
  let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }

  let!(:restricted_build) { create(:ci_build, :success, name: 'metrics', pipeline: pipeline) }

  before do
    stub_licensed_features(metrics_reports: true)
    # Metrics report whose own artifact access is maintainer-only.
    create(:ee_ci_job_artifact, :metrics, :maintainer_only_access, job: restricted_build)
  end

  describe '#accessible_metrics_reports' do
    it 'excludes maintainer-only content from a reporter' do
      expect(pipeline.accessible_metrics_reports(reporter).metrics).to be_empty
    end

    it 'includes it for a user who can read maintainer artifacts' do
      expect(pipeline.accessible_metrics_reports(maintainer).metrics).to be_present
    end

    it 'treats a nil (anonymous) user as unable to read restricted content' do
      expect(pipeline.accessible_metrics_reports(nil).metrics).to be_empty
    end
  end

  it 'still returns everything via the unscoped #metrics_report' do
    expect(pipeline.metrics_report.metrics).to be_present
  end
end
