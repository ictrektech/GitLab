# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::SecurityFinding::CreateMergeRequestService, '#execute', feature_category: :vulnerability_management do
  include_context 'with dependency scanning security report findings'

  let_it_be(:default_organization) { create(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- merge request creation reads instance AI settings

  let_it_be(:scan) do
    create(
      :security_scan,
      :latest_successful,
      scan_type: :dependency_scanning,
      pipeline: pipeline,
      build: artifact.job
    )
  end

  let_it_be(:security_finding) do
    create(
      :security_finding,
      severity: report_finding.severity,
      uuid: report_finding.uuid,
      scan: scan
    )
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:current_user) { user }

  subject do
    described_class.new(project: project, current_user: current_user, params: {
      security_finding: security_finding
    }).execute
  end

  before do
    stub_licensed_features(security_dashboard: true)
    group.add_maintainer(user)
  end

  context 'when user does not have permission to read_security_resource' do
    let_it_be(:user_not_member_of_project) { create(:user) }
    let_it_be(:current_user) { user_not_member_of_project }

    it 'raises an error' do
      expect { subject }.to raise_error Gitlab::Access::AccessDeniedError
    end
  end

  context 'when user does not have permission to create merge request' do
    before do
      allow_next_instance_of(MergeRequests::CreateFromVulnerabilityDataService) do |instance|
        allow(instance).to receive(:can?).with(user, :create_merge_request_in, project).and_return(false)
      end
    end

    it 'propagates the error' do
      expect(subject).not_to be_success
      expect(subject.message).to eq('User is not permitted to create merge request')
    end
  end

  context 'when there is an existing vulnerability for the security finding' do
    let_it_be(:vulnerability_finding, freeze: false) do
      create(
        :vulnerabilities_finding_with_remediation,
        :with_remediation,
        :identifier,
        :detected,
        uuid: report_finding.uuid,
        project: project,
        report_type: :dependency_scanning,
        summary: 'Test remediation',
        raw_metadata: report_finding.raw_metadata,
        pipeline: pipeline
      )
    end

    let_it_be(:vulnerability) do
      create(
        :vulnerability,
        report_type: :dependency_scanning,
        project: project,
        findings: [vulnerability_finding],
        present_on_default_branch: true
      )
    end

    before do
      allow_next_instance_of(Commits::CommitPatchService) do |service|
        allow(service).to receive(:execute).and_return({ status: :success })
      end
    end

    it 'does not create a new Vulnerability, but creates a new MergeRequest, and a MergeRequestLink' do
      expect { subject }
        .to not_change { project.vulnerabilities.count }
        .and(change { MergeRequest.count }.by(1))
        .and(change { Vulnerabilities::MergeRequestLink.count }.by(1))
    end

    it 'does not change the vulnerability present_on_default_branch value' do
      expect { subject }.not_to change { vulnerability.reload.present_on_default_branch }
    end

    it 'returns a successful response' do
      response = subject
      expect(response.message).to be_blank
      expect(response.payload[:merge_request]).to be_present
    end
  end

  context 'when there is no vulnerability for the security finding' do
    it 'does create a new Vulnerability, MergeRequest,and MergeRequestLink' do
      expect { subject }.to change {
        project.vulnerabilities.count
      }.by(1)
       .and(change { MergeRequest.count }.by(1))
       .and(change { Vulnerabilities::MergeRequestLink.count }.by(1))
    end

    it 'sets the new vulnerability present_on_default_branch to false' do
      service_response = subject

      merge_request = service_response.payload.fetch(:merge_request)
      vulnerability = Vulnerabilities::MergeRequestLink.find_by(merge_request: merge_request).vulnerability

      expect(vulnerability.present_on_default_branch).to be false
    end

    it 'sets the new vulnerability state to detected' do
      service_response = subject

      merge_request = service_response.payload.fetch(:merge_request)
      vulnerability = Vulnerabilities::MergeRequestLink.find_by(merge_request: merge_request).vulnerability

      expect(vulnerability.state).to eq 'detected'
    end
  end

  context 'when there is an existing confirmed vulnerability for the security finding' do
    let_it_be(:vulnerability_finding, freeze: false) do
      create(
        :vulnerabilities_finding_with_remediation,
        :with_remediation,
        :identifier,
        :detected,
        uuid: report_finding.uuid,
        project: project,
        report_type: :dependency_scanning,
        summary: 'Test remediation',
        raw_metadata: report_finding.raw_metadata,
        pipeline: pipeline
      )
    end

    let_it_be_with_reload(:vulnerability) do
      create(
        :vulnerability,
        :confirmed,
        report_type: :dependency_scanning,
        project: project,
        findings: [vulnerability_finding],
        present_on_default_branch: true
      )
    end

    shared_examples 'keeps the existing vulnerability unchanged' do
      it 'returns the error and does not destroy or change the vulnerability', :aggregate_failures do
        expect { expect(subject.message).to eq(error_message) }
          .to not_change { Vulnerability.exists?(vulnerability.id) }.from(true)
          .and not_change { vulnerability_finding.reload.vulnerability_id }.from(vulnerability.id)
          .and not_change { vulnerability.reload.state }.from('confirmed')
          .and not_change { vulnerability.state_transitions.count }
          .and not_change { Note.where(noteable: vulnerability).count }
          .and not_change(MergeRequest, :count)
          .and not_change(Vulnerabilities::MergeRequestLink, :count)

        expect(subject).not_to be_success
      end
    end

    context 'when the merge request is created' do
      before do
        allow_next_instance_of(Commits::CommitPatchService) do |service|
          allow(service).to receive(:execute).and_return({ status: :success })
        end
      end

      it 'creates a merge request and link, then moves the vulnerability to detected', :aggregate_failures do
        expect { subject }
          .to change { vulnerability.reload.state }.from('confirmed').to('detected')
          .and change { vulnerability.state_transitions.count }.by(1)
          .and change { MergeRequest.count }.by(1)
          .and change { Vulnerabilities::MergeRequestLink.where(vulnerability: vulnerability).count }.by(1)
          .and not_change { project.vulnerabilities.count }
      end
    end

    context 'when the remediation patch does not apply' do
      let(:error_message) { 'Unable to apply patch' }

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the merge request creation fails' do
      let(:error_message) { 'Invalid vulnerability category' }

      before do
        allow_next_instance_of(MergeRequests::CreateFromVulnerabilityDataService) do |instance|
          allow(instance).to receive(:execute).and_return(ServiceResponse.error(message: error_message))
        end
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the merge request link creation fails' do
      let(:error_message) { 'Merge request is already linked to this vulnerability' }

      before do
        allow_next_instance_of(Commits::CommitPatchService) do |service|
          allow(service).to receive(:execute).and_return({ status: :success })
        end

        allow_next_instance_of(VulnerabilityMergeRequestLinks::CreateService) do |instance|
          allow(instance).to receive(:execute).and_return(ServiceResponse.error(message: error_message))
        end
      end

      it_behaves_like 'keeps the existing vulnerability unchanged'
    end

    context 'when the deferred state update fails' do
      let(:error) { ActiveRecord::RecordInvalid.new }

      before do
        allow_next_instance_of(Commits::CommitPatchService) do |service|
          allow(service).to receive(:execute).and_return({ status: :success })
        end

        allow_next_instance_of(Vulnerabilities::FindOrCreateFromSecurityFindingService) do |instance|
          allow(instance).to receive(:update_existing_state).and_raise(error)
        end

        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'returns the created merge request, keeps it and its link, and tracks the exception', :aggregate_failures do
        expect { subject }
          .to change { MergeRequest.count }.by(1)
          .and change { Vulnerabilities::MergeRequestLink.where(vulnerability: vulnerability).count }.by(1)
          .and not_change { vulnerability.reload.state }.from('confirmed')

        merge_request = subject.payload[:merge_request]

        expect(subject).to be_success
        expect(merge_request).to be_persisted
        expect(Vulnerabilities::MergeRequestLink.exists?(vulnerability: vulnerability, merge_request: merge_request))
          .to be(true)
        expect(Gitlab::ErrorTracking).to have_received(:track_exception)
          .with(error, vulnerability_id: vulnerability.id, security_finding_uuid: security_finding.uuid)
      end
    end
  end

  shared_examples 'an error occurs' do
    it 'propagates the error' do
      expect(subject).not_to be_success
      expect(subject.message).to eq(error_message)
    end

    it 'does not create a new Vulnerability, MergeRequest, and MergeRequestLink' do
      expect { subject }
        .to not_change { project.vulnerabilities.count }
        .and not_change(Vulnerabilities::MergeRequestLink, :count)
        .and not_change(MergeRequest, :count)
    end
  end

  context 'when a error occurs during the merge request creation' do
    let(:error_message) { 'Invalid vulnerability category' }
    let(:error_response) { ServiceResponse.error(message: error_message) }

    before do
      allow_next_instance_of(MergeRequests::CreateFromVulnerabilityDataService) do |instance|
        allow(instance).to receive(:execute).and_return(error_response)
      end
    end

    it_behaves_like 'an error occurs'
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

  context 'when a error occurs during the merge link creation' do
    let(:error_message) { 'Merge request is already linked to this vulnerability' }
    let(:error_response) { ServiceResponse.error(message: error_message) }

    before do
      allow_next_instance_of(VulnerabilityMergeRequestLinks::CreateService) do |instance|
        allow(instance).to receive(:execute).and_return(error_response)
      end
    end

    it_behaves_like 'an error occurs'
  end
end
