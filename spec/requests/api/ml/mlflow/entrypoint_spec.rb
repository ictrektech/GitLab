# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ml::Mlflow::Entrypoint, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:candidate) { create(:ml_candidates, project: project, user: developer) }
  let_it_be(:model) { create(:ml_models, project: project) }
  let_it_be(:token) { create(:personal_access_token, scopes: %w[api], user: developer) }

  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:base_route) { "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow" }
  let(:statement_timeout) do
    ActiveRecord::QueryCanceled.new('PG::QueryCanceled: ERROR:  canceling statement due to statement timeout')
  end

  shared_examples 'an MLflow endpoint that handles database errors' do
    before do
      allow(finder_class).to receive(finder_method).and_raise(error)
    end

    context 'when a statement times out' do
      let(:error) { statement_timeout }

      it 'tracks the error and returns a generic message', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'BAD_REQUEST', 'message' => 'Request timed out')
      end

      it 'tracks the error with the user and remote IP from the API request context' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception) do
          expect(Gitlab::ApplicationContext.current)
            .to include('meta.user' => developer.username, 'meta.remote_ip' => '127.0.0.1')
        end

        request
      end

      it 'logs the exception class in the API log' do
        expect(API::API::LOG_FORMATTER).to receive(:call) do |_severity, _datetime, _, data|
          expect(data.stringify_keys).to include('exception.class' => 'ActiveRecord::QueryCanceled')
        end

        request
      end
    end

    context 'when another database error occurs' do
      let(:error) { ActiveRecord::StatementInvalid.new('PG::UndefinedColumn: ERROR:  column "x" does not exist') }

      it 'tracks the error and returns a generic message', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'BAD_REQUEST', 'message' => 'Database error')
      end
    end

    context 'when a transient database error occurs' do
      where(error_class: [
        ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::ConnectionFailed,
        ActiveRecord::Deadlocked, ActiveRecord::SerializationFailure, ActiveRecord::LockWaitTimeout
      ])

      with_them do
        let(:error) { error_class.new('PG error') }

        it 'tracks the error and returns TEMPORARILY_UNAVAILABLE so the client retries', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

          request

          expect(response).to have_gitlab_http_status(:service_unavailable)
          expect(json_response).to eq(
            'error_code' => 'TEMPORARILY_UNAVAILABLE',
            'message' => 'Temporary database error'
          )
        end
      end
    end

    context 'when a value violates a column constraint' do
      where(error_class: [ActiveRecord::NotNullViolation, ActiveRecord::ValueTooLong, ActiveRecord::RangeError])

      with_them do
        let(:error) { error_class.new('PG error DETAIL:  Failing row contains (1, 2, key, null).') }

        it 'returns a generic invalid parameter message without tracking', :aggregate_failures do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response).to eq(
            'error_code' => 'INVALID_PARAMETER_VALUE',
            'message' => 'A parameter value is missing, too long, or out of range'
          )
        end
      end
    end

    context 'when a record is not found' do
      let(:error) { ActiveRecord::RecordNotFound.new("Couldn't find the record") }

      it 'returns the message as an invalid parameter', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => error.message)
      end
    end

    context 'when a unique constraint is violated' do
      let(:error) do
        ActiveRecord::RecordNotUnique.new(
          'PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint ' \
            'DETAIL:  Key (project_id, name)=(1, name) already exists.'
        )
      end

      it 'returns RESOURCE_ALREADY_EXISTS', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'RESOURCE_ALREADY_EXISTS')
      end
    end

    context 'when a record is invalid' do
      let(:error) { ActiveRecord::RecordInvalid.new(build(:ml_models, name: nil).tap(&:validate)) }

      it 'returns the validation message', :aggregate_failures do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => error.message)
      end
    end

    context 'when mlflow_database_error_handling is disabled' do
      where(error_class: [
        ActiveRecord::QueryCanceled, ActiveRecord::StatementInvalid, ActiveRecord::NotNullViolation,
        ActiveRecord::RecordNotUnique, ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked
      ])

      with_them do
        let(:error) { error_class.new('PG error DETAIL:  Failing row contains (1, 2, key, null).') }

        before do
          stub_feature_flags(mlflow_database_error_handling: false)
        end

        it 'returns the database message as an invalid parameter', :aggregate_failures do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response).to eq('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => error.message)
        end
      end
    end
  end

  describe 'GET runs/get' do
    let(:request) { get api("#{base_route}/runs/get"), params: { run_id: candidate.eid }, headers: headers }
    let(:finder_class) { Ml::Candidate }
    let(:finder_method) { :with_project_id_and_eid }

    it_behaves_like 'an MLflow endpoint that handles database errors'
  end

  describe 'GET registered-models/get' do
    let(:request) { get api("#{base_route}/registered-models/get"), params: { name: model.name }, headers: headers }
    let(:finder_class) { Ml::Model }
    let(:finder_method) { :by_project_id_and_name }

    it_behaves_like 'an MLflow endpoint that handles database errors'
  end

  context 'when the token lookup times out' do
    let(:request) { get api("#{base_route}/runs/get"), params: { run_id: candidate.eid }, headers: headers }

    before do
      allow(PersonalAccessToken).to receive(:find_by_token).and_raise(statement_timeout)
    end

    it 'does not repeat the lookup and returns a generic message', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(statement_timeout)

      request

      expect(PersonalAccessToken).to have_received(:find_by_token).once
      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response).to eq('error_code' => 'BAD_REQUEST', 'message' => 'Request timed out')
    end

    context 'when mlflow_database_error_handling is disabled' do
      before do
        stub_feature_flags(mlflow_database_error_handling: false)
      end

      it 'does not repeat the lookup and returns the database message', :aggregate_failures do
        request

        expect(PersonalAccessToken).to have_received(:find_by_token).once
        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response).to eq('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => statement_timeout.message)
      end
    end
  end
end
