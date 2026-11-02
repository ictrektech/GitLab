# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Analytics::CycleAnalytics::SummaryController, feature_category: :value_stream_management do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project) }

  let(:params) { { namespace_id: project.namespace.to_param, project_id: project.to_param, created_after: '2010-01-01', created_before: '2010-02-01' } }

  before do
    sign_in(user)
  end

  describe 'GET "show"' do
    subject { get :show, params: params }

    it 'succeeds' do
      project.add_reporter(user)

      subject

      expect(response).to be_successful
      expect(response).to match_response_schema('analytics/cycle_analytics/summary')
    end

    context 'when the date range is longer than 180 days' do
      before do
        params[:created_after] = '2009-01-01'
      end

      it 'renders 422' do
        project.add_reporter(user)

        subject

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors']['created_after']).to include('The given date range is larger than 180 days')
      end
    end

    context 'when the date range is exactly 180 days' do
      before do
        params[:created_before] = '2010-06-30'
      end

      it 'succeeds' do
        project.add_reporter(user)

        subject

        expect(response).to be_successful
      end
    end

    context 'when an anonymous user requests a public project' do
      let_it_be(:project) { create(:project, :public) }

      before do
        sign_out(user)
      end

      it 'succeeds' do
        subject

        expect(response).to be_successful
      end

      it 'renders 422 when the date range is longer than 180 days' do
        params[:created_after] = '2009-01-01'

        subject

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
      end
    end

    context 'when analytics_disabled features are disabled' do
      it 'renders 404' do
        project.add_reporter(user)
        project.project_feature.update!(analytics_access_level: ProjectFeature::DISABLED)

        subject

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user is not part of the project' do
      it 'renders 404' do
        subject

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when filters are applied' do
      let_it_be(:author) { create(:user) }
      let_it_be(:milestone) { create(:milestone, title: 'milestone 1', project: project) }
      let_it_be(:issue_with_author) { create(:issue, project: project, author: author, created_at: Date.new(2010, 1, 15)) }
      let_it_be(:issue_with_other_author) { create(:issue, project: project, author: user, created_at: Date.new(2010, 1, 15)) }
      let_it_be(:issue_with_milestone) { create(:issue, project: project, milestone: milestone, created_at: Date.new(2010, 1, 15)) }

      before_all do
        project.add_reporter(user)
      end

      it 'filters by author username' do
        params[:author_username] = author.username

        subject

        expect(response).to be_successful

        issue_count = json_response.first
        expect(issue_count['value']).to eq('1')
      end

      it 'filters by milestone title' do
        params[:milestone_title] = milestone.title

        subject

        expect(response).to be_successful

        issue_count = json_response.first
        expect(issue_count['value']).to eq('1')
      end
    end
  end
end
