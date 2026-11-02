# frozen_string_literal: true

require 'spec_helper'

# The database error aborts the surrounding transaction, so this spec uses table deletion instead.
RSpec.describe API::Ml::Mlflow::Entrypoint, :delete, feature_category: :mlops do
  let(:project) { create(:project) }
  let(:developer) { create(:user, developer_of: project) }
  let(:candidate) { create(:ml_candidates, project: project, user: developer) }
  let(:token) { create(:personal_access_token, scopes: %w[api], user: developer) }

  let(:request) do
    post api("/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/runs/log-batch"),
      params: { run_id: candidate.eid, params: [{ key: 'p', value: 'a' * 251 }] },
      headers: { 'Authorization' => "Bearer #{token.token}" },
      as: :json
  end

  context 'when a param value is over the column limit' do
    it 'returns a generic invalid parameter message without tracking', :aggregate_failures do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      request

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response).to eq(
        'error_code' => 'INVALID_PARAMETER_VALUE',
        'message' => 'A parameter value is missing, too long, or out of range'
      )
    end

    context 'when mlflow_database_error_handling is disabled' do
      before do
        stub_feature_flags(mlflow_database_error_handling: false)
      end

      it 'returns the database message', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('PG::CheckViolation')
      end
    end
  end
end
