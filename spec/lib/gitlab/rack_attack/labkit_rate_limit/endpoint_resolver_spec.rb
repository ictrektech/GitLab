# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RackAttack::LabkitRateLimit::EndpointResolver, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  describe '#endpoint_id' do
    subject(:endpoint_id) { described_class.instance.endpoint_id(env) }

    let(:env) { Rack::MockRequest.env_for(path, method: method) }

    where(:method, :path, :expected) do
      'GET'     | '/api/v4/projects'                       | 'GET /api/:version/projects'
      'POST'    | '/api/v4/projects'                       | 'POST /api/:version/projects'
      'HEAD'    | '/api/v4/projects'                       | 'HEAD /api/:version/projects'
      'OPTIONS' | '/api/v4/projects'                       | nil
      'OPTIONS' | '/api/v4/no-such-endpoint'               | nil
      'DELETE'  | '/api/v4/projects'                       | nil
      'HEAD'    | '/users/sign_in'                         | 'SessionsController#new'
      'GET'     | '/api/v4/projects/123/issues'            | 'GET /api/:version/projects/:id/issues'
      'GET'     | '/api/v4/groups/gitlab-org%2Fsub/issues' | 'GET /api/:version/groups/:id/issues'
      'POST'    | '/api/graphql'                           | 'GraphqlController#execute'
      'GET'     | '/users/sign_in'                         | 'SessionsController#new'
      'GET'     | '/gitlab-org/gitlab.git/info/refs'       | 'Repositories::GitHttpController#info_refs'
      'POST'    | '/gitlab-org/gitlab.git/git-upload-pack' | 'Repositories::GitHttpController#git_upload_pack'
      'GET'     | '/dashboard/issues.ics'                  | 'DashboardController#issues_calendar'
      'GET'     | '/dashboard/issues'                      | 'DashboardController#issues'
      'GET'     | '/admin/sidekiq'                         | nil
      'GET'     | '/groups/gitlab-org/-/archived'          | nil
    end

    with_them do
      it { is_expected.to eq(expected) }
    end

    context 'when the route needs a database constraint to resolve' do
      where(path: %w[/gitlab-org/gitlab /gitlab-org/gitlab/-/issues /groups/gitlab-org/-/issues])

      with_them do
        let(:method) { 'GET' }

        it 'returns nil without querying the database' do
          recorder = ActiveRecord::QueryRecorder.new { expect(endpoint_id).to be_nil }

          expect(recorder.count).to eq(0)
        end
      end
    end

    # EE only: CE has no controller route guarded only by a constraint class the resolver does not know.
    context 'when the route has a constraint class the resolver does not know', if: Gitlab.ee? do
      let(:method) { 'GET' }
      let(:path) { '/-/trials/new' }

      it { is_expected.to be_nil }
    end

    context 'when a constraint raises' do
      let(:method) { 'GET' }
      let(:path) { '/users/sign_in' }

      before do
        Rails.application.routes.routes
          .flat_map { |route| route.app.respond_to?(:constraints) ? route.app.constraints : [] }
          .grep(Namespaces::GroupUrlConstraint)
          .each { |constraint| allow(constraint).to receive(:matches?).and_raise(StandardError) }
      end

      it 'treats the route as unresolved' do
        expect(endpoint_id).to be_nil
      end
    end

    context 'when the API path matches no endpoint' do
      let(:method) { 'GET' }
      let(:path) { '/api/v4/no-such-endpoint' }

      it 'returns nil, as the catch-all records no endpoint_id' do
        expect(endpoint_id).to be_nil
      end
    end

    it 'answers every route lambda from the minimal request, without querying the database' do
      lambdas = Rails.application.routes.routes.flat_map do |route|
        route.app.respond_to?(:constraints) ? route.app.constraints.grep(Proc) : []
      end
      request = ActionDispatch::Request.new(
        'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'SCRIPT_NAME' => '', 'QUERY_STRING' => '',
        'rack.input' => StringIO.new
      )

      recorder = ActiveRecord::QueryRecorder.new do
        lambdas.each do |constraint|
          expect { constraint.call(request) }.not_to raise_error
        end
      end

      expect(lambdas).not_to be_empty
      expect(recorder.count).to eq(0)
    end

    it 'does not mutate the env' do
      env = Rack::MockRequest.env_for('/api/v4/projects')
      original = env.dup

      described_class.instance.endpoint_id(env)

      expect(env).to eq(original)
    end

    # Grape serves the first route of the method whose pattern matches, so that route's
    # endpoint_id is what the request would have recorded.
    it 'agrees with Grape for every API route without path params', :aggregate_failures do
      routes = Gitlab::RequestEndpoints.all_api_endpoints

      routes.each do |route|
        next if route.request_method == '*' || route.origin.delete_prefix('/api/:version').match?(/[:*]/)

        path = route.origin.sub(':version', Array(route.version).first.to_s)
        served = routes.find do |candidate|
          candidate.request_method == route.request_method && candidate.pattern.match?(path)
        end

        expect(described_class.instance.endpoint_id(Rack::MockRequest.env_for(path, method: route.request_method)))
          .to eq(API::Base.endpoint_id_for_route(served)), "#{route.request_method} #{path}"
      end
    end
  end
end
