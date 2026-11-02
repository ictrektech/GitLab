# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ml::Mlflow::RegisteredModels, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:model) do
    create(:ml_models, :with_metadata, project: project)
  end

  let_it_be(:model_version) { create(:ml_model_versions, project: project, model: model, version: '1.0.0') }

  let_it_be(:tokens) do
    {
      write: create(:personal_access_token, scopes: %w[read_api api], user: developer),
      read: create(:personal_access_token, scopes: %w[read_api], user: developer),
      no_access: create(:personal_access_token, scopes: %w[read_user], user: developer),
      different_user: create(:personal_access_token, scopes: %w[read_api api], user: build(:user))
    }
  end

  let(:current_user) { developer }
  let(:access_token) { tokens[:write] }
  let(:headers) { { 'Authorization' => "Bearer #{access_token.token}" } }
  let(:project_id) { project.id }
  let(:default_params) { {} }
  let(:params) { default_params }
  let(:request) { get api(route), params: params, headers: headers }
  let(:json_response) { Gitlab::Json.parse(api_response.body) }

  subject(:api_response) do
    request
    response
  end

  def rendered_count
    body = Gitlab::Json.parse(response.body)
    models = Array.wrap(body['registered_model'] || body['registered_models'])

    models.sum { |m| 1 + m['tags'].size + m['latest_versions'].sum { |v| 1 + v['tags'].size } }
  end

  def create_model_version(model, **attributes)
    create(:ml_model_versions, model: model, project: model.project, **attributes).tap do |model_version|
      create(:ml_model_version_metadata, model_version: model_version, project: model.project)
    end
  end

  describe 'GET /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/get' do
    it_behaves_like 'authorizing granular token permissions', :read_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/get"
        get api("#{p}?name=#{model.name}", personal_access_token: pat)
      end
    end

    let(:model_name) { model.name }
    let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/get?name=#{model_name}" }

    it 'returns the model', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      is_expected.to match_response_schema('ml/get_model')
    end

    context 'when the model has several versions' do
      let_it_be(:model_with_versions) { create(:ml_models, :with_metadata, project: project) }
      let_it_be(:versions) do
        %w[1.0.0 3.0.0 2.0.0].map { |version| create_model_version(model_with_versions, version: version) }
      end

      let(:model_name) { model_with_versions.name }
      let(:latest_versions) { json_response.dig('registered_model', 'latest_versions') }

      def perform_request
        get api(route), headers: headers
      end

      def add_records
        create_model_version(model_with_versions)
        create_model_version(model_with_versions)
      end

      it 'returns only the latest version', :aggregate_failures do
        is_expected.to have_gitlab_http_status(:ok)
        expect(latest_versions.pluck('version')).to eq([versions[1].id.to_s])
      end

      # Only the latest version is rendered, so tags on it are what grows.
      it_behaves_like 'MLflow|a request with constant queries' do
        def add_records
          create_model_version(model_with_versions)
          create(:ml_model_metadata, model: model_with_versions)
          create(:ml_model_version_metadata, model_version: versions[1], project: project)
        end
      end

      context 'when mlflow_bounded_list_responses is disabled' do
        before do
          stub_feature_flags(mlflow_bounded_list_responses: false)
        end

        it 'returns every version', :aggregate_failures do
          is_expected.to have_gitlab_http_status(:ok)
          expect(latest_versions.pluck('version')).to match_array(versions.map { |v| v.id.to_s })
        end

        it_behaves_like 'MLflow|a request with constant queries'
      end
    end

    describe 'Error States' do
      context 'when has access' do
        context 'and model does not exist' do
          let(:model_name) { 'foo' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and name is not passed' do
          let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/get" }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read-only model registry resource'
    end
  end

  describe 'GET /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/alias' do
    it_behaves_like 'authorizing granular token permissions', :read_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/alias"
        get api("#{p}?name=#{model.name}&alias=#{model_version.version}", personal_access_token: pat)
      end
    end

    let(:model_name) { model_version.model.name }
    let(:version) { model_version.version }
    let(:route) do
      "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/alias?name=#{model_name}&alias=#{version}"
    end

    it 'returns the model version', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)

      expect(json_response['model_version']['name']).to eq(model_name)
      expect(json_response['model_version']['aliases']).to eq([version])
    end

    describe 'Error States' do
      context 'when has access' do
        context 'and model does not exist' do
          let(:model_name) { 'foo' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and model version does not exist' do
          let(:version) { '1.0.1' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and name is not passed' do
          let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/alias" }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and alias is not passed' do
          let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/alias?name=#{model_name}" }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read-only model registry resource'
    end
  end

  describe 'POST /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/create' do
    it_behaves_like 'authorizing granular token permissions', :create_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/create"
        post api(p, personal_access_token: pat), params: { name: "gpat-model-#{SecureRandom.hex(4)}" }
      end
    end

    let(:route) do
      "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/create"
    end

    let(:params) { { name: 'my-model-name' } }
    let(:request) { post api(route), params: params, headers: headers }

    it 'creates the model', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      expect(json_response).to include('registered_model')
    end

    describe 'tags limit' do
      let(:params) { { name: 'my-model-name', tags: Array.new(tags_count) { |i| { key: "tag#{i}", value: 'v' } } } }
      let(:request) { post api(route), params: params, headers: headers, as: :json }

      context 'when tags are over the default limit' do
        let(:tags_count) { 101 }

        it 'rejects the request without creating the model', :aggregate_failures do
          is_expected.to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('A request can contain at most 100 tags. Got 101 tags.')
          expect(Ml::Model.find_by(project: project, name: 'my-model-name')).to be_nil
        end
      end

      context 'with the limit stubbed to 2 tags' do
        before do
          # Tags are inserted one at a time, so a small limit keeps the at-the-limit request under the query limit.
          stub_const('API::Ml::Mlflow::ApiHelpers::MAX_TAGS_PER_CREATE_REQUEST', 2)
        end

        context 'when tags are at the limit' do
          let(:tags_count) { 2 }

          it 'creates the model with every tag', :aggregate_failures do
            is_expected.to have_gitlab_http_status(:ok)
            expect(json_response['registered_model']['tags'].size).to eq(2)
          end
        end

        context 'when tags are over the limit' do
          let(:tags_count) { 3 }

          it 'rejects the request without creating the model', :aggregate_failures do
            is_expected.to have_gitlab_http_status(:bad_request)
            expect(json_response).to eq(
              'error_code' => 'INVALID_PARAMETER_VALUE',
              'message' => 'A request can contain at most 2 tags. Got 3 tags.'
            )
            expect(Ml::Model.find_by(project: project, name: 'my-model-name')).to be_nil
          end

          context 'when mlflow_enforce_request_limits is disabled' do
            before do
              stub_feature_flags(mlflow_enforce_request_limits: false)
            end

            it 'creates the model with every tag', :aggregate_failures do
              is_expected.to have_gitlab_http_status(:ok)
              expect(json_response['registered_model']['tags'].size).to eq(3)
            end
          end
        end
      end
    end

    describe 'Error States' do
      context 'when the model name is not passed' do
        let(:params) { {} }

        it_behaves_like 'MLflow|an invalid request'
      end

      context 'when the model name already exists' do
        let(:existing_model) do
          create(:ml_models, user: current_user, project: project)
        end

        let(:params) { { name: existing_model.name } }

        it "is Bad Request", :aggregate_failures do
          is_expected.to have_gitlab_http_status(:bad_request)

          expect(json_response).to include({ 'error_code' => 'RESOURCE_ALREADY_EXISTS' })
        end
      end

      context 'when project does not exist' do
        let(:route) { "/projects/#{non_existing_record_id}/ml/mlflow/api/2.0/mlflow/registered-models/create" }

        it "is Not Found", :aggregate_failures do
          is_expected.to have_gitlab_http_status(:not_found)

          expect(json_response['message']).to eq('404 Project Not Found')
        end
      end

      # TODO: Ensure consisted error responses https://gitlab.com/gitlab-org/gitlab/-/issues/429731
      context 'when a duplicate tag name is supplied' do
        let(:params) do
          { name: 'my-model-name', tags: [{ key: 'key1', value: 'value1' }, { key: 'key1', value: 'value2' }] }
        end

        it "creates the model with only the second tag", :aggregate_failures do
          expect(json_response).to include({ 'error_code' => 'RESOURCE_ALREADY_EXISTS' })
        end
      end

      # TODO: Ensure consisted error responses https://gitlab.com/gitlab-org/gitlab/-/issues/429731
      context 'when an empty tag name is supplied' do
        let(:params) do
          { name: 'my-model-name', tags: [{ key: '', value: 'value1' }, { key: 'key1', value: 'value2' }] }
        end

        it "creates the model with only the second tag", :aggregate_failures do
          expect(json_response).to include({ 'error_code' => 'RESOURCE_ALREADY_EXISTS' })
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read/write model registry resource'
    end
  end

  describe 'PATCH /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/update' do
    it_behaves_like 'authorizing granular token permissions', :update_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/update"
        patch api(p, personal_access_token: pat), params: { name: model.name, description: "d" }
      end
    end

    let(:model_name) { model.name }
    let(:model_description) { 'updated model description' }
    let(:params) { { name: model_name, description: model_description } }
    let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/update" }
    let(:request) { patch api(route), params: params, headers: headers }

    it 'returns the updated model', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      is_expected.to match_response_schema('ml/update_model')
      expect(json_response["registered_model"]["description"]).to eq(model_description)
    end

    context 'when the model has several versions' do
      let_it_be(:latest_version) { create_model_version(model, version: '2.0.0') }

      let(:latest_versions) { json_response.dig('registered_model', 'latest_versions') }

      it 'returns only the latest version' do
        expect(latest_versions.pluck('version')).to eq([latest_version.id.to_s])
      end

      context 'when mlflow_bounded_list_responses is disabled' do
        before do
          stub_feature_flags(mlflow_bounded_list_responses: false)
        end

        it 'returns every version' do
          expect(latest_versions.pluck('version')).to match_array([model_version, latest_version].map { |v| v.id.to_s })
        end

        it_behaves_like 'MLflow|a request with constant queries' do
          def perform_request
            patch api(route), params: params, headers: headers
          end

          def add_records
            2.times { create_model_version(model) }
          end
        end
      end
    end

    describe 'Error States' do
      context 'when has access' do
        context 'and model does not exist' do
          let(:model_name) { 'foo' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and name is not passed' do
          let(:params) { { description: model_description } }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read/write model registry resource'
    end
  end

  describe 'POST /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/get-latest-versions' do
    it_behaves_like 'authorizing granular token permissions', :read_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/get-latest-versions"
        post api(p, personal_access_token: pat), params: { name: model.name }
      end
    end

    let_it_be(:version1) { create(:ml_model_versions, model: model, created_at: 1.week.ago) }
    let_it_be(:version2) { create(:ml_model_versions, model: model, created_at: 1.day.ago) }

    let(:model_name) { model.name }
    let(:params) { { name: model_name } }
    let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/get-latest-versions" }
    let(:request) { post api(route), params: params, headers: headers }

    it 'returns an array with the most recently created model version', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      is_expected.to match_response_schema('ml/get_latest_versions')
      expect(json_response["model_versions"][0]["name"]).to eq(model_name)
      expect(json_response["model_versions"][0]["version"]).to eq(version2.id.to_s)
    end

    describe 'Error States' do
      context 'when has access' do
        context 'and model does not exist' do
          let(:model_name) { 'foo' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and name is not passed' do
          let(:params) { {} }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read-only model registry resource'
    end
  end

  describe 'DELETE /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/delete' do
    it_behaves_like 'authorizing granular token permissions', :delete_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        p = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/delete"
        delete api(p, personal_access_token: pat), params: { name: model.name }
      end
    end

    let(:model_name) { model.name }
    let(:params) { { name: model_name } }
    let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/delete" }
    let(:request) { delete api(route), params: params, headers: headers }

    it 'returns a success response', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      expect(json_response).to eq({})
    end

    describe 'Error States' do
      context 'when destroy fails' do
        it 'returns an error' do
          allow(Ml::DestroyModelService).to receive_message_chain(:new,
            :execute).and_return(ServiceResponse.error(message: ""))

          is_expected.to have_gitlab_http_status(:bad_request)
          expect(json_response["message"]).to eq("Model could not be deleted")
        end
      end

      context 'when has access' do
        context 'and model does not exist' do
          let(:model_name) { 'foo' }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end

        context 'and name is not passed' do
          let(:params) { {} }

          it_behaves_like 'MLflow|Not Found - Resource Does Not Exist'
        end
      end

      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read/write model registry resource'
    end
  end

  describe 'GET /projects/:id/ml/mlflow/api/2.0/mlflow/registered-models/search' do
    it_behaves_like 'authorizing granular token permissions', :read_ml_model do
      let(:boundary_object) { project }
      let(:user) { developer }
      let(:request) do
        base = "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow/registered-models/search"
        get api(base, personal_access_token: pat)
      end
    end

    let_it_be(:model2) do
      create(:ml_models, :with_metadata, project: project)
    end

    let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/search" }

    it 'returns all the models', :aggregate_failures do
      is_expected.to have_gitlab_http_status(:ok)
      is_expected.to match_response_schema('ml/list_models')
      expect(json_response["registered_models"].count).to be(2)
    end

    context 'when models have several versions' do
      let_it_be(:latest_version) { create_model_version(model, version: '2.0.0') }

      let(:latest_versions) do
        json_response['registered_models'].to_h { |m| [m['name'], m['latest_versions'].pluck('version').sort] }
      end

      def perform_request
        get api(route), headers: headers
      end

      def add_records
        2.times do
          new_model = create(:ml_models, :with_metadata, project: project)
          3.times { create_model_version(new_model) }
        end
      end

      it 'returns only the latest version of each model' do
        expect(latest_versions).to eq(model.name => [latest_version.id.to_s], model2.name => [])
      end

      it_behaves_like 'MLflow|a request with constant queries'

      context 'when mlflow_bounded_list_responses is disabled' do
        before do
          stub_feature_flags(mlflow_bounded_list_responses: false)
        end

        it 'returns every version of each model' do
          expect(latest_versions).to eq(
            model.name => [model_version.id.to_s, latest_version.id.to_s].sort,
            model2.name => []
          )
        end

        it_behaves_like 'MLflow|a request with constant queries'
      end
    end

    context "with a valid filter supplied" do
      let(:filter) { "name='#{model2.name}'" }
      let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/search?filter=#{filter}" }

      it 'returns only the models for the given filter' do
        is_expected.to have_gitlab_http_status(:ok)
        expect(json_response["registered_models"].count).to be(1)
      end
    end

    context "with an invalid filter supplied" do
      let(:filter) { "description='foo'" }
      let(:route) { "/projects/#{project_id}/ml/mlflow/api/2.0/mlflow/registered-models/search?filter=#{filter}" }

      it 'returns an error' do
        is_expected.to have_gitlab_http_status(:bad_request)

        expect(json_response).to include({ 'error_code' => 'INVALID_PARAMETER_VALUE' })
      end
    end

    describe 'Error States' do
      it_behaves_like 'MLflow|an authenticated resource'
      it_behaves_like 'MLflow|a read-only model registry resource'
    end
  end
end
