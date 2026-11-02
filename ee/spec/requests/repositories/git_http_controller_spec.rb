# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Repositories::GitHttpController, feature_category: :source_code_management do
  include GitHttpHelpers
  include ::EE::GeoHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:user_personal_key) { create(:personal_key, user: user) }
  let_it_be(:project) { create(:project, :repository, :private, developers: user) }

  let(:env) { { user: user.username, password: user.password } }
  let(:path) { "#{project.full_path}.git" }

  describe 'POST #git_upload_pack' do
    context 'geo pulls a personal snippet' do
      let_it_be(:snippet) { create(:personal_snippet, :repository, author: user) }
      let_it_be(:path) { "snippets/#{snippet.id}.git" }

      before do
        allow(::Gitlab::Geo::JwtRequestDecoder).to receive(:geo_auth_attempt?).and_return(true)
      end

      it 'allows access' do
        allow_any_instance_of(::Gitlab::Geo::JwtRequestDecoder).to receive(:decode).and_return({ scope: "snippets/#{snippet.id}" })

        clone_get(path, **env)

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'does not allow access if scope is wrong' do
        allow_any_instance_of(::Gitlab::Geo::JwtRequestDecoder).to receive(:decode).and_return({ scope: "wron-scope" })

        clone_get(path, **env)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when ssh certificates are enforced for the top-level group' do
      let_it_be_with_reload(:group) { create(:group) }
      let_it_be(:project) { create(:project, :public, :repository, group: group) }
      let_it_be(:user) { create(:enterprise_user, enterprise_group: group) }

      before do
        stub_licensed_features(ssh_certificates: group)

        group.namespace_settings.enforce_ssh_certificates = true
        group.save!

        group.add_developer(user)
      end

      context 'and repository is cloned from build' do
        let_it_be_with_reload(:job) { create(:ci_build, status: :running, user: user) }

        let(:env) { { user: Gitlab::Auth::CI_JOB_USER, password: job.token } }

        it 'executes successfully' do
          clone_get(path, **env)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end
  end

  describe 'POST #ssh_upload_pack' do
    subject(:make_request) { post "/#{path}/ssh-upload-pack", headers: headers }

    let(:geo_node) { create(:geo_node, :primary) }
    let(:headers) { workhorse_header.merge(geo_header) }
    let(:workhorse_header) { workhorse_internal_api_request_header }
    let(:geo_header) { Gitlab::Geo::BaseRequest.new(scope: project.full_path, gl_id: "key-#{user_personal_key.id}").headers }

    before do
      stub_current_geo_node(geo_node)
    end

    it 'allows access' do
      make_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to include(
        "GL_ID" => "user-#{user.id}",
        "GL_REPOSITORY" => "project-#{project.id}",
        "GL_USERNAME" => user.username,
        "NeedAudit" => true,
        "ShowAllRefs" => true
      )
    end

    it 'runs GitAccess authorization for Geo SSH requests', :aggregate_failures do
      expect_next_instance_of(::Gitlab::GitAccessProject) do |access|
        expect(access).to receive(:check).with('git-upload-pack', ::Gitlab::GitAccess::ANY).and_call_original
      end

      make_request

      expect(response).to have_gitlab_http_status(:ok)
    end

    context 'when Workhorse header is missing', :verify_workhorse_jwt do
      let(:workhorse_header) { {} }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq 'Nil JSON web token'
      end
    end

    context 'when Workhorse header is incorrect', :verify_workhorse_jwt do
      let(:workhorse_header) { { Gitlab::Workhorse::INTERNAL_API_REQUEST_HEADER => 'wrong' } }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq 'Not enough or too many segments'
      end
    end

    context 'when Geo auth header is missing' do
      let(:geo_header) { {} }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when Geo auth header is invalid' do
      let(:geo_header) { { 'Authorization' => 'GL-Geo wrong' } }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.body).to eq 'Geo JWT authentication failed: Bad token'
      end
    end
  end

  describe 'POST #ssh_receive_pack' do
    subject(:make_request) { post "/#{path}/ssh-receive-pack", headers: headers }

    let(:geo_node) { create(:geo_node, :primary) }
    let(:headers) { workhorse_header.merge(geo_header) }
    let(:workhorse_header) { workhorse_internal_api_request_header }
    let(:geo_header) { Gitlab::Geo::BaseRequest.new(scope: project.full_path, gl_id: "key-#{user_personal_key.id}").headers }

    before do
      stub_current_geo_node(geo_node)
    end

    it 'allows access' do
      make_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to include(
        "GL_ID" => "user-#{user.id}",
        "GL_REPOSITORY" => "project-#{project.id}",
        "GL_USERNAME" => user.username,
        "NeedAudit" => true,
        "ShowAllRefs" => true
      )
    end

    context 'when Workhorse header is missing', :verify_workhorse_jwt do
      let(:workhorse_header) { {} }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq 'Nil JSON web token'
      end
    end

    context 'when Workhorse header is incorrect', :verify_workhorse_jwt do
      let(:workhorse_header) { { Gitlab::Workhorse::INTERNAL_API_REQUEST_HEADER => 'wrong' } }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq 'Not enough or too many segments'
      end
    end

    context 'when Geo auth header is missing' do
      let(:geo_header) { {} }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when Geo auth header is invalid' do
      let(:geo_header) { { 'Authorization' => 'GL-Geo wrong' } }

      it 'returns an error' do
        make_request

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.body).to eq 'Geo JWT authentication failed: Bad token'
      end
    end
  end

  describe 'Shell JWT client IP claim' do
    include GitlabShellHelpers
    using RSpec::Parameterized::TableSyntax

    let_it_be(:group) { create(:group) }
    let_it_be(:ip_restricted_project) { create(:project, :repository, :private, group: group, developers: user) }
    let_it_be(:deploy_key) { create(:deploy_key, write_access_to: ip_restricted_project) }

    let(:path) { "#{ip_restricted_project.full_path}.git" }
    let(:user_claims) { { 'gl_id' => "user-#{user.id}" } }
    let(:deploy_key_claims) do
      { 'gl_id' => "user-#{deploy_key.user.id}", 'gl_key_id' => deploy_key.id, 'gl_key_type' => 'deploy_key' }
    end

    let(:headers) do
      workhorse_internal_api_request_header.merge(gitlab_shell_internal_api_request_header(claims: claims))
    end

    before_all do
      create(:ip_restriction, group: group, range: '150.168.0.1')
    end

    before do
      stub_licensed_features(group_ip_restriction: true)
      # Allow request.ip so the outcome depends on the check_ip claim alone.
      stub_application_setting(globally_allowed_ips: '127.0.0.1')
    end

    shared_examples 'enforcing group IP restrictions with the Shell JWT client IP' do
      context 'with a check_ip claim' do
        where(:actor_claims, :check_ip, :status) do
          ref(:user_claims)       | '150.168.0.1' | :ok
          ref(:user_claims)       | '150.168.0.2' | :not_found
          ref(:deploy_key_claims) | '150.168.0.1' | :ok
          ref(:deploy_key_claims) | '150.168.0.2' | :not_found
        end

        with_them do
          let(:claims) { actor_claims.merge('check_ip' => check_ip) }

          it 'enforces the restriction against check_ip' do
            make_request

            expect(response).to have_gitlab_http_status(status)
          end
        end
      end

      context 'without a check_ip claim' do
        let(:claims) { user_claims }

        where(:globally_allowed_ips, :status) do
          '127.0.0.1' | :ok
          ''          | :not_found
        end

        with_them do
          before do
            stub_application_setting(globally_allowed_ips: globally_allowed_ips)
          end

          it 'enforces the restriction against request.ip' do
            make_request

            expect(response).to have_gitlab_http_status(status)
          end
        end
      end

      context 'when the cells_shell_jwt_key_claims feature flag is disabled' do
        let(:claims) { user_claims.merge('check_ip' => '150.168.0.2') }

        before do
          stub_feature_flags(cells_shell_jwt_key_claims: false)
        end

        it 'enforces the restriction against request.ip' do
          make_request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'for POST /ssh-upload-pack' do
      subject(:make_request) { post "/#{path}/ssh-upload-pack", headers: headers }

      it_behaves_like 'enforcing group IP restrictions with the Shell JWT client IP'
    end

    context 'for POST /ssh-receive-pack' do
      subject(:make_request) { post "/#{path}/ssh-receive-pack", headers: headers }

      it_behaves_like 'enforcing group IP restrictions with the Shell JWT client IP'
    end
  end

  describe 'GET #info_refs' do
    context 'smartcard session required' do
      subject(:request) { clone_get(path, **env) }

      before do
        stub_licensed_features(smartcard_auth: true)
        stub_smartcard_setting(enabled: true, required_for_git_access: true)

        project.add_developer(user)
      end

      context 'user with a smartcard session', :clean_gitlab_redis_sessions do
        let(:session_id) { '42' }
        let(:stored_session) do
          { 'smartcard_signins' => { 'last_signin_at' => 5.minutes.ago } }
        end

        before do
          Gitlab::Redis::Sessions.with do |redis|
            redis.set("session:gitlab:#{session_id}", Marshal.dump(stored_session))
            redis.sadd("session:lookup:user:gitlab:#{user.id}", [session_id])
          end
        end

        it "allows access" do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'user without a smartcard session' do
        it "does not allow access" do
          request

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(response.body).to eq('Project requires smartcard login. Please login to GitLab using a smartcard.')
        end
      end

      context 'with the setting off' do
        before do
          stub_smartcard_setting(required_for_git_access: false)
        end

        it "allows access" do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end
  end

  describe 'POST #git_receive_pack' do
    subject { push_post(path, **env) }

    context 'when node is a primary Geo one' do
      before do
        stub_primary_node
      end

      shared_examples 'triggers Geo' do
        it 'executes ::Gitlab::Geo::GitPushHttp' do
          expect_next_instance_of(::Gitlab::Geo::GitPushHttp) do |instance|
            expect(instance).to receive(:cache_referrer_node)
          end

          subject
        end

        it 'returns 200' do
          subject

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'with projects' do
        it_behaves_like 'triggers Geo'
      end

      context 'with a project wiki' do
        let_it_be(:wiki) { create(:project_wiki, :empty_repo, project: project) }
        let_it_be(:path) { "#{wiki.full_path}.git" }

        it_behaves_like 'triggers Geo'
      end

      context 'with a group wiki' do
        include WikiHelpers

        let_it_be_with_reload(:group) { create(:group, :wiki_repo) }
        let_it_be(:user) { create(:user) }

        let(:path) { "#{group.wiki.full_path}.git" }

        before_all do
          group.add_owner(user)
        end

        before do
          stub_group_wikis(true)
        end

        it_behaves_like 'triggers Geo'
      end

      context 'with a personal snippet' do
        let_it_be(:snippet) { create(:personal_snippet, :repository, author: user) }
        let_it_be(:path) { "snippets/#{snippet.id}.git" }

        it_behaves_like 'triggers Geo'
      end

      context 'with a project snippet' do
        let_it_be(:snippet) { create(:project_snippet, :repository, author: user, project: project) }
        let_it_be(:path) { "#{project.full_path}/snippets/#{snippet.id}.git" }

        it_behaves_like 'triggers Geo'
      end
    end
  end
end
