# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::MergeRequests::SaveMergeRequestReviewService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, :public) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:duo_bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

  let(:service) { described_class.new(name: 'save_merge_request_review') }
  let(:request) { instance_double(ActionDispatch::Request) }
  let(:token) { create(:personal_access_token, user: user, scopes: [:mcp]) }
  let(:params) do
    {
      arguments: {
        project_id: project.id.to_s,
        merge_request_iid: merge_request.iid,
        method: 'post_duo_review'
      }
    }
  end

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user, access_token: token)
  end

  describe '#execute with method post_duo_review' do
    context 'when Duo Code Review is available' do
      before do
        allow_next_found_instance_of(::MergeRequest) do |instance|
          allow(instance).to receive(:ai_review_merge_request_allowed?).with(user).and_return(true)
          allow(instance).to receive(:duo_code_review_progress_note).and_return(progress_note)
        end
      end

      let(:progress_note) { nil }

      context 'with a granular token' do
        let(:token) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: token_permissions)
        end

        context 'without the required permission' do
          let(:token_permissions) { :read_merge_request }

          it 'does not request a review', :aggregate_failures do
            expect(::Ai::DuoWorkflows::CodeReview::RequestReviewFromBot).not_to receive(:new)

            result = service.execute(request: request, params: params)

            expect(result[:reason]).to eq(:unauthorized)
            expect(result[:content].first[:text]).to include('Access denied')
          end
        end

        context 'with the required permission' do
          let(:token_permissions) { :update_merge_request }

          it 'requests a review', :aggregate_failures do
            expect_next_instance_of(::Ai::DuoWorkflows::CodeReview::RequestReviewFromBot) do |request_review|
              expect(request_review).to receive(:execute) do
                merge_request.reviewers << duo_bot
                { status: :success }
              end
            end

            result = service.execute(request: request, params: params)

            expect(result[:isError]).to be(false)
            expect(result[:structuredContent]['status']).to eq('review_requested')
          end
        end
      end

      context 'when a review is already in progress' do
        let(:progress_note) { instance_double(Note) }

        it 'acknowledges without requesting another review', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]['status']).to eq('already_in_progress')
          expect(result[:structuredContent]['merge_request_url']).to eq(::Gitlab::UrlBuilder.build(merge_request))
        end
      end

      context 'when the Duo bot is not yet a reviewer' do
        it 'assigns the bot as reviewer and reports the request', :aggregate_failures do
          expect_next_instance_of(
            ::MergeRequests::UpdateReviewersService,
            project: project,
            current_user: user,
            params: { reviewer_ids: [duo_bot.id] }
          ) do |reviewers_service|
            expect(reviewers_service).to receive(:execute) do
              merge_request.reviewers << duo_bot
            end
          end

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]['method']).to eq('post_duo_review')
          expect(result[:structuredContent]['status']).to eq('review_requested')
        end

        it 'reports a failure when the bot does not end up as reviewer' do
          expect_next_instance_of(::MergeRequests::UpdateReviewersService) do |reviewers_service|
            expect(reviewers_service).to receive(:execute)
          end

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('could not be assigned as reviewer')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        end
      end

      context 'when the Duo bot is already a reviewer' do
        before_all do
          merge_request.reviewers << duo_bot
        end

        it 'requests a re-review from the bot', :aggregate_failures do
          expect_next_instance_of(
            ::MergeRequests::RequestReviewService,
            project: project,
            current_user: user
          ) do |review_service|
            expect(review_service).to receive(:execute)
              .with(merge_request, duo_bot)
              .and_return({ status: :success })
          end

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]['status']).to eq('review_requested')
        end

        it 'surfaces a re-review failure', :aggregate_failures do
          expect_next_instance_of(::MergeRequests::RequestReviewService) do |review_service|
            expect(review_service).to receive(:execute)
              .with(merge_request, duo_bot)
              .and_return({ status: :error, message: 'Reviewer not found' })
          end

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Reviewer not found')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
        end
      end
    end

    context 'when the caller has no Duo Code Review access' do
      it 'reports unauthorized with the availability message', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:content].first[:text]).to include('GitLab Duo Code Review is not available')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end
    end

    context 'when a reporter with Duo Code Review access requests a review' do
      let_it_be(:reporter) { create(:user, reporter_of: project) }
      let_it_be(:review_merge_request) do
        create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let(:params) do
        {
          arguments: {
            project_id: project.id.to_s,
            merge_request_iid: review_merge_request.iid,
            method: 'post_duo_review'
          }
        }
      end

      let(:token) { create(:personal_access_token, user: reporter, scopes: [:mcp]) }

      before do
        allow(::Gitlab::Duo::CodeReview).to receive(:enabled?).and_return(true)
        service.set_cred(current_user: reporter, access_token: token)
      end

      it 'reports a first review the bot cannot be assigned to as unauthorized', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:content].first[:text])
          .to eq('Failed to request Duo Code Review: the Duo bot could not be assigned as reviewer.')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        expect(review_merge_request.reload.reviewers).not_to include(duo_bot)
      end

      it 'reports a re-review it cannot request as unauthorized', :aggregate_failures do
        review_merge_request.reviewers << duo_bot

        result = service.execute(request: request, params: params)

        expect(result[:content].first[:text]).to eq('Failed to request Duo Code Review: Invalid permissions')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end
    end
  end

  describe '#execute with method approve' do
    let_it_be_with_reload(:approve_project) { create(:project, :repository, :public, developers: [user]) }
    let_it_be(:approve_merge_request) { create(:merge_request, source_project: approve_project) }
    let(:params) do
      { arguments: { project_id: approve_project.id.to_s, merge_request_iid: approve_merge_request.iid,
                     method: 'approve' } }
    end

    before do
      stub_licensed_features(merge_request_approvers: true)
    end

    context 'when the instance requires a password to approve' do
      before do
        approve_project.update!(require_password_to_approve: true)
      end

      it 'surfaces the re-authentication fallback error', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('password or SAML re-authentication requirement')
        expect(approve_merge_request.reset.approved_by?(user)).to be(false)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:error)
      end
    end

    context 'when the author cannot approve their own merge request' do
      let(:token) { create(:personal_access_token, user: approve_merge_request.author, scopes: [:mcp]) }

      before_all do
        approve_project.add_developer(approve_merge_request.author)
      end

      before do
        approve_project.update!(merge_requests_author_approval: false)
        service.set_cred(current_user: approve_merge_request.author, access_token: token)
      end

      it 'names the eligibility restriction instead of blaming re-authentication', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('authors or committers')
        expect(approve_merge_request.reset.approved_by?(approve_merge_request.author)).to be(false)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end
    end
  end
end
