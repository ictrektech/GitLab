# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::SecurityFinding::CreateIssueService, '#execute',
  feature_category: :vulnerability_management do
  before do
    stub_licensed_features(security_dashboard: true)
  end

  let_it_be_with_reload(:project) { create(:project, :repository) }
  let_it_be_with_reload(:pipeline) { create(:ci_pipeline, :success) }

  let_it_be_with_reload(:build_sast) { create(:ci_build, :success, name: 'sast', pipeline: pipeline) }
  let_it_be_with_reload(:artifact_sast) do
    create(:ee_ci_job_artifact, :sast_with_signatures_and_vulnerability_flags,
      job: build_sast)
  end

  let_it_be_with_reload(:report_sast) { create(:ci_reports_security_report, pipeline: pipeline, type: :sast) }
  let_it_be_with_reload(:scan_sast) do
    create(:security_scan, :latest_successful, scan_type: :sast, build: artifact_sast.job)
  end

  let_it_be_with_reload(:user) { create(:user, developer_of: project) }
  # `freeze: false` is required here: this `let_it_be` subject is a mutable
  # Array that the service under test appends to; freezing it raises
  # FrozenError. Keep the opt-out (see gitlab-org/gitlab#602925).
  let_it_be(:sast_security_findings, freeze: false) { [] }

  let(:security_finding) { sast_security_findings.first }
  let(:security_finding_uuid) { security_finding.uuid }
  let(:params) { { security_finding_uuid: security_finding_uuid } }

  before_all do
    sast_content = File.read(artifact_sast.file.path)
    Gitlab::Ci::Parsers::Security::Sast.parse!(sast_content, report_sast)
    report_sast.merge!(report_sast)
    sast_security_findings.push(*insert_security_findings(report_sast, scan_sast))
  end

  subject { described_class.new(project: project, current_user: user, params: params).execute }

  context 'when user does not have permission to read_security_resource' do
    let(:user_not_member_of_project) { create(:user) }

    subject do
      described_class.new(project: project,
        current_user: user_not_member_of_project,
        params: params).execute
    end

    it 'raises an error' do
      expect { subject }.to raise_error Gitlab::Access::AccessDeniedError
    end
  end

  context 'when user does not have permission to create issue' do
    before do
      allow_next_instance_of(Issues::CreateFromVulnerabilityService) do |instance|
        allow(instance).to receive(:can?).with(user, :create_issue, project).and_return(false)
      end
    end

    it 'propagates the error' do
      expect(subject).not_to be_success
      expect(subject.message).to eq('User is not permitted to create issue')
    end
  end

  context 'when there is no vulnerability finding and vulnerability for the security finding' do
    it 'does create a new Vulnerability' do
      expect { subject }.to change { project.vulnerabilities.count }.from(0).to(1)
      expect(project.vulnerabilities.last.present_on_default_branch).to be false
    end

    it 'sets the new vulnerability present_on_default_branch to false' do
      service_response = subject
      vulnerability = service_response.payload.fetch(:issue).vulnerability_links.first.vulnerability
      expect(vulnerability.present_on_default_branch).to be false
    end

    it 'sets the new vulnerability state to detected' do
      service_response = subject
      vulnerability = service_response.payload.fetch(:issue).vulnerability_links.first.vulnerability
      expect(vulnerability.state).to eq 'detected'
    end

    it 'does create a new Issue' do
      expect { subject }.to change { Issue.count }.by(1)
    end

    it 'does create a new IssueLink' do
      expect { subject }.to change { Vulnerabilities::IssueLink.count }.by(1)
    end
  end

  context 'when there is an existing vulnerability finding and vulnerability for the security finding' do
    let_it_be_with_reload(:finding) do
      create(:vulnerabilities_finding, :detected,
        report_type: :sast, project: project, uuid: sast_security_findings.first.uuid)
    end

    let_it_be_with_reload(:vulnerability) do
      create(:vulnerability, report_type: :sast, project: project, findings: [finding], present_on_default_branch: true)
    end

    it 'does not create a new Vulnerability' do
      expect { subject }.not_to change { project.vulnerabilities.count }
    end

    it 'does not change the Vulnerability present_on_default_branch value' do
      expect { subject }.not_to change { vulnerability.reload.present_on_default_branch }
    end

    it 'does create a new Issue' do
      expect { subject }.to change { Issue.count }.by(1)
    end

    it 'does create a new IssueLink' do
      expect { subject }.to change { Vulnerabilities::IssueLink.count }.by(1)
    end
  end

  context 'when there is an existing confirmed vulnerability for the security finding' do
    let_it_be_with_reload(:finding) do
      create(:vulnerabilities_finding, :detected,
        report_type: :sast, project: project, uuid: sast_security_findings.first.uuid)
    end

    let_it_be_with_reload(:vulnerability) do
      create(:vulnerability, :confirmed, report_type: :sast, project: project, findings: [finding],
        present_on_default_branch: true)
    end

    shared_examples 'keeps the existing vulnerability unchanged' do
      it 'returns the error and does not destroy or change the vulnerability', :aggregate_failures do
        expect { expect(subject.message).to eq(error_message) }
          .to not_change { Vulnerability.exists?(vulnerability.id) }.from(true)
          .and not_change { finding.reload.vulnerability_id }.from(vulnerability.id)
          .and not_change { vulnerability.reload.state }.from('confirmed')
          .and not_change { vulnerability.state_transitions.count }
          .and not_change { Note.where(noteable: vulnerability).count }
          .and not_change { Issue.count }

        expect(subject).not_to be_success
      end
    end

    it 'creates an issue and link, then moves the vulnerability to detected', :aggregate_failures do
      expect { subject }
        .to change { vulnerability.reload.state }.from('confirmed').to('detected')
        .and change { vulnerability.state_transitions.count }.by(1)
        .and change { Issue.count }.by(1)
        .and change { Vulnerabilities::IssueLink.where(vulnerability: vulnerability).count }.by(1)
        .and not_change { project.vulnerabilities.count }
    end

    context 'when the vulnerability already has a created issue link' do
      let(:error_message) { 'Vulnerability already has a "created" issue link' }

      let_it_be(:existing_issue) { create(:issue, project: project) }
      let_it_be(:existing_link) do
        create(:vulnerabilities_issue_link, :created, vulnerability: vulnerability, issue: existing_issue)
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'

      it 'keeps the existing issue link' do
        subject

        expect(Vulnerabilities::IssueLink.exists?(existing_link.id)).to be(true)
      end
    end

    context 'when issues are disabled in the project' do
      let(:error_message) { 'User is not permitted to create issue' }

      before do
        project.project_feature.update!(issues_access_level: ProjectFeature::DISABLED)
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the user is an auditor' do
      let(:error_message) { 'User is not permitted to create issue' }

      let_it_be(:auditor) { create(:user, :auditor) }

      subject { described_class.new(project: project, current_user: auditor, params: params).execute }

      before do
        stub_licensed_features(security_dashboard: true, auditor_user: true)
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the issue link creation fails' do
      let(:error_message) { 'Issue link error' }

      before do
        allow_next_instance_of(VulnerabilityIssueLinks::CreateService) do |instance|
          allow(instance).to receive(:execute).and_return(ServiceResponse.error(message: error_message))
        end
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the deferred state update fails' do
      let(:error) { ActiveRecord::RecordInvalid.new }

      before do
        allow_next_instance_of(Vulnerabilities::FindOrCreateFromSecurityFindingService) do |instance|
          allow(instance).to receive(:update_existing_state).and_raise(error)
        end

        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'returns the created issue, keeps it and its link, and tracks the exception', :aggregate_failures do
        expect { subject }
          .to change { Issue.count }.by(1)
          .and change { Vulnerabilities::IssueLink.where(vulnerability: vulnerability).count }.by(1)
          .and not_change { vulnerability.reload.state }.from('confirmed')

        issue = subject.payload[:issue]

        expect(subject).to be_success
        expect(issue).to be_persisted
        expect(Vulnerabilities::IssueLink.exists?(vulnerability: vulnerability, issue: issue)).to be(true)
        expect(Gitlab::ErrorTracking).to have_received(:track_exception)
          .with(error, vulnerability_id: vulnerability.id, security_finding_uuid: security_finding_uuid)
      end
    end
  end

  context 'when issues are disabled and there is no vulnerability for the security finding' do
    before do
      project.project_feature.update!(issues_access_level: ProjectFeature::DISABLED)
    end

    it 'rolls back the vulnerability it created', :aggregate_failures do
      expect { expect(subject).not_to be_success }.not_to change { project.vulnerabilities.count }
    end
  end

  shared_examples 'an error occurs' do
    it 'propagates the error' do
      expect(subject).not_to be_success
      expect(subject.message).to eq(error_message)
    end

    it 'does not create a new Vulnerability' do
      expect { subject }.not_to change { project.vulnerabilities.count }
    end

    it 'does not create a new Issue' do
      expect { subject }.not_to change { Issue.count }
    end

    it 'does not create a new IssueLink' do
      expect { subject }.not_to change { Vulnerabilities::IssueLink.count }
    end
  end

  context 'when a error occurs during the vulnerability creation' do
    let(:error_message) { 'Security Finding not found' }
    let(:error_response) { ServiceResponse.error(message: error_message) }

    before do
      allow_next_instance_of(Vulnerabilities::FindOrCreateFromSecurityFindingService) do |instance|
        allow(instance).to receive(:execute).and_return(error_response)
      end
    end

    it_behaves_like 'an error occurs'
  end

  context 'when a error occurs during the issue creation' do
    let(:error_message) { 'Invalid vulnerability category' }
    let(:error_response) { ServiceResponse.error(message: error_message) }

    before do
      allow_next_instance_of(Issues::CreateFromVulnerabilityService) do |instance|
        allow(instance).to receive(:execute).and_return(error_response)
      end
    end

    it_behaves_like 'an error occurs'
  end

  context 'when a error occurs during the issue link creation' do
    let(:error_message) { 'Vulnerability already has a "created" issue link' }
    let(:error_response) { ServiceResponse.error(message: error_message) }

    before do
      allow_next_instance_of(VulnerabilityIssueLinks::CreateService) do |instance|
        allow(instance).to receive(:execute).and_return(error_response)
      end
    end

    it_behaves_like 'an error occurs'
  end

  def insert_security_findings(report, scan)
    report.findings.map do |finding|
      create(
        :security_finding,
        severity: finding.severity,
        uuid: finding.uuid,
        scan: scan
      )
    end
  end
end
