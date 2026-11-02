# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::FeedbackPolicy, feature_category: :vulnerability_management do
  include ExternalAuthorizationServiceHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :public, namespace: owner.namespace) }

  let(:current_user) { owner }

  subject { described_class.new(current_user, vulnerability_feedback) }

  it 'delegates to the project policy' do
    feedback = build_stubbed(:vulnerability_feedback, project: project)

    expect(described_class.new(current_user, feedback)).to delegate_to(ProjectPolicy)
  end

  describe 'create_vulnerability_feedback' do
    context 'when the user is able to create issues in the project' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      before_all do
        project.add_developer(owner)
      end

      it { expect_allowed(:create_vulnerability_feedback) }
    end

    context 'when issue cannot be created' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      context 'when issues feature is disabled' do
        before do
          project.project_feature.update!(issues_access_level: ProjectFeature::DISABLED)
        end

        it 'does not allow to create issue feedback' do
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have permission to create issue in project' do
        subject { described_class.new(nil, vulnerability_feedback) }

        it 'does not allow to create issue feedback' do
          expect_disallowed(:create_issue)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end
    end

    context 'when merge request cannot be created' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      context 'when merge request feature is disabled' do
        before do
          project.project_feature.update!(merge_requests_access_level: ProjectFeature::DISABLED)
        end

        it 'does not allow to create merge request feedback' do
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have permission to create merge_request in project' do
        subject { described_class.new(nil, vulnerability_feedback) }

        it 'does not allow to create merge request feedback' do
          expect_disallowed(:create_merge_request_in)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'when user does not have developer permission' do
        # guest can create merge request IN
        let_it_be(:guest) { create(:user, guest_of: project) }

        subject { described_class.new(guest, vulnerability_feedback) }

        it 'does not allow to create merge request feedback' do
          expect_allowed(:create_merge_request_in)
          expect_disallowed(:create_vulnerability_feedback)
        end
      end

      context 'with security bot' do
        let_it_be(:current_user) { create(:user, :security_bot) }

        it { expect_disallowed(:create_vulnerability_feedback) }
      end
    end
  end

  describe 'update_vulnerability_feedback' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when feedback type is issue' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      it 'does not allow to update issue feedback' do
        expect_disallowed(:update_vulnerability_feedback)
      end
    end

    context 'when feedback type is merge_request' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      it 'does not allow to update merge request feedback' do
        expect_disallowed(:update_vulnerability_feedback)
      end
    end

    context 'when feedback type is dismissal' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :dismissal) }

      it 'allows to update dismissal feedback' do
        expect_allowed(:update_vulnerability_feedback)
      end
    end
  end

  describe 'destroy_vulnerability_feedback' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when feedback type is issue' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :issue) }

      it 'does not allow to destroy issue feedback' do
        expect_disallowed(:destroy_vulnerability_feedback)
      end
    end

    context 'when feedback type is merge_request' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :merge_request) }

      it 'does not allow to destroy merge request feedback' do
        expect_disallowed(:destroy_vulnerability_feedback)
      end
    end

    context 'when feedback type is dismissal' do
      let(:vulnerability_feedback) { Vulnerabilities::Feedback.new(project: project, feedback_type: :dismissal) }

      it 'allows to destroy dismissal feedback' do
        expect_allowed(:destroy_vulnerability_feedback)
      end
    end
  end
end
