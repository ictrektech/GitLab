# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Repositories::GitHttpController, feature_category: :source_code_management do
  include GitHttpHelpers
  include GitlabShellHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, :private, developers: user) }
  let_it_be(:public_project) { create(:project, :repository, :public) }

  let(:path) { "#{project.full_path}.git" }

  def shell_headers(claims)
    workhorse_internal_api_request_header.merge(gitlab_shell_internal_api_request_header(claims: claims))
  end

  def deploy_key_claims(deploy_key)
    { 'gl_id' => "user-#{deploy_key.user.id}", 'gl_key_id' => deploy_key.id, 'gl_key_type' => 'deploy_key' }
  end

  shared_examples 'rejecting the Shell JWT claims' do |reason|
    let(:expected_gl_key_id) { nil }
    let(:expected_project_path) { project.full_path }

    it 'returns not found without a Workhorse payload and logs the reason', :aggregate_failures do
      allow(Gitlab::AuthLogger).to receive(:warn).and_call_original
      expect(Gitlab::AuthLogger).to receive(:warn).with(
        hash_including(
          Labkit::Fields::LOG_MESSAGE => 'Rejected Gitlab-Shell-Api-Request claims',
          Labkit::Fields::ADDITIONAL_DETAILS => "#{reason}, gl_key_id: #{expected_gl_key_id.inspect}",
          Labkit::Fields::GL_PROJECT_PATH => expected_project_path
        )
      ).and_call_original

      make_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(response.body).not_to include('GL_ID')
    end
  end

  shared_examples 'rejecting an unverified Shell JWT client IP' do
    it 'returns not found without using check_ip', :aggregate_failures do
      allow(::Gitlab::IpAddressState).to receive(:with).and_call_original
      expect(::Gitlab::IpAddressState).not_to receive(:with).with('1.2.3.4')

      make_request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'an SSH-over-HTTP endpoint honouring Shell JWT key and client IP claims' do
    let_it_be(:ownerless_deploy_key) { create(:deploy_key, readonly_access_to: project) }

    context 'with an expired deploy key' do
      let_it_be(:expired_deploy_key) { create(:deploy_key, :expired, readonly_access_to: project) }

      let(:headers) { shell_headers(deploy_key_claims(expired_deploy_key)) }

      it 'denies access through GitAccess', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq('Your SSH key has expired.')
      end
    end

    context 'with an unknown gl_key_id' do
      let(:headers) do
        shell_headers(deploy_key_claims(ownerless_deploy_key).merge('gl_key_id' => non_existing_record_id))
      end

      it_behaves_like 'rejecting the Shell JWT claims', :deploy_key_not_found do
        let(:expected_gl_key_id) { non_existing_record_id }
      end
    end

    context 'with a personal key id claimed as a deploy key' do
      let_it_be(:personal_key) { create(:personal_key, user: user) }

      let(:headers) do
        shell_headers('gl_id' => "user-#{user.id}", 'gl_key_id' => personal_key.id, 'gl_key_type' => 'deploy_key')
      end

      it_behaves_like 'rejecting the Shell JWT claims', :deploy_key_not_found do
        let(:expected_gl_key_id) { personal_key.id }
      end
    end

    context 'with a signing-only deploy key' do
      let_it_be(:signing_deploy_key) { create(:deploy_key, usage_type: :signing, readonly_access_to: project) }

      let(:headers) { shell_headers(deploy_key_claims(signing_deploy_key)) }

      it_behaves_like 'rejecting the Shell JWT claims', :deploy_key_not_found do
        let(:expected_gl_key_id) { signing_deploy_key.id }
      end
    end

    context 'when gl_id does not match the deploy key user' do
      let(:headers) { shell_headers(deploy_key_claims(ownerless_deploy_key).merge('gl_id' => "user-#{user.id}")) }

      it_behaves_like 'rejecting the Shell JWT claims', :deploy_key_user_mismatch do
        let(:expected_gl_key_id) { ownerless_deploy_key.id }
      end
    end

    context 'with a deploy key type but no gl_key_id' do
      let(:headers) { shell_headers(deploy_key_claims(ownerless_deploy_key).except('gl_key_id')) }

      it_behaves_like 'rejecting the Shell JWT claims', :invalid_gl_key_id
    end

    context 'with a malformed check_ip' do
      let(:headers) { shell_headers('gl_id' => "user-#{user.id}", 'check_ip' => 'garbage') }

      it_behaves_like 'rejecting the Shell JWT claims', :invalid_check_ip

      context 'when the repository does not exist' do
        let(:path) { "#{project.namespace.full_path}/non-existent.git" }

        it_behaves_like 'rejecting the Shell JWT claims', :invalid_check_ip do
          let(:expected_project_path) { nil }
        end
      end
    end

    context 'with a regular key type claim' do
      let_it_be(:personal_key) { create(:personal_key, user: user) }

      let(:headers) do
        shell_headers('gl_id' => "user-#{user.id}", 'gl_key_id' => personal_key.id, 'gl_key_type' => 'key')
      end

      it 'keeps the user as the GitAccess actor', :aggregate_failures do
        expect(::Gitlab::GitAccessProject).to receive(:new).with(
          user, project, 'ssh', hash_including(authentication_abilities: anything)
        ).and_call_original

        make_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['GL_ID']).to eq("user-#{user.id}")
      end
    end

    context 'with a user and check_ip claim' do
      let(:headers) { shell_headers('gl_id' => "user-#{user.id}", 'check_ip' => '1.2.3.4') }

      it 'uses check_ip as the client IP and decodes the JWT once', :aggregate_failures do
        expect(::Gitlab::Shell).to receive(:verify_api_request).once.and_call_original
        allow(::Gitlab::IpAddressState).to receive(:with).and_call_original
        expect(::Gitlab::IpAddressState).to receive(:with).with('1.2.3.4').once.and_call_original
        expect(::Gitlab::GitAccessProject).to receive(:new).with(
          user, project, 'ssh', hash_including(authentication_abilities: anything)
        ).and_call_original

        log_metadata = nil
        subscriber = ->(_name, _start, _finish, _id, payload) { log_metadata = payload[:metadata] }
        ActiveSupport::Notifications.subscribed(subscriber, 'process_action.action_controller') { make_request }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['GL_ID']).to eq("user-#{user.id}")
        expect(json_response.dig('GitalyServer', 'call_metadata', 'remote_ip')).to eq('1.2.3.4')
        expect(log_metadata).to include('meta.remote_ip' => '1.2.3.4')
      end
    end

    context 'when the cells_shell_jwt_key_claims feature flag is disabled' do
      let(:headers) { shell_headers(deploy_key_claims(ownerless_deploy_key).merge('check_ip' => '1.2.3.4')) }

      before do
        stub_feature_flags(cells_shell_jwt_key_claims: false)
      end

      it 'ignores the claims and decodes the JWT once', :aggregate_failures do
        expect(::Gitlab::Shell).to receive(:verify_api_request).once.and_call_original
        allow(::Gitlab::IpAddressState).to receive(:with).and_call_original
        expect(::Gitlab::IpAddressState).not_to receive(:with).with('1.2.3.4')

        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq('This action cannot be performed by internal users')
      end

      context 'with a malformed check_ip for a user with access' do
        let(:headers) { shell_headers('gl_id' => "user-#{user.id}", 'check_ip' => 'garbage') }

        it 'allows access without logging a claims rejection', :aggregate_failures do
          allow(Gitlab::AuthLogger).to receive(:warn).and_call_original
          expect(Gitlab::AuthLogger).not_to receive(:warn).with(
            hash_including(Labkit::Fields::LOG_MESSAGE => 'Rejected Gitlab-Shell-Api-Request claims')
          )

          make_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['GL_ID']).to eq("user-#{user.id}")
        end
      end
    end
  end

  shared_examples 'a shell-authenticated SSH-over-HTTP endpoint rejecting unauthenticated requests' do
    context 'with valid Shell JWT but user without access' do
      let_it_be(:other_user) { create(:user) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{other_user.id}" })
        )
      end

      it 'returns not found to avoid revealing project existence' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with valid Shell JWT for a blocked member' do
      let_it_be(:blocked) { create(:user, :blocked) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{blocked.id}" })
        )
      end

      before_all do
        project.add_developer(blocked)
      end

      it 'rejects the blocked user without leaking a Workhorse Gitaly payload', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq('Your account has been blocked.')
        expect(response.body).not_to include('GL_ID')
        expect(response.media_type).not_to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
      end
    end

    context 'with valid Shell JWT for a deactivated member' do
      let_it_be(:deactivated) { create(:user, :deactivated) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{deactivated.id}" })
        )
      end

      before_all do
        project.add_developer(deactivated)
      end

      it 'rejects the deactivated user without leaking a Workhorse Gitaly payload', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to include('deactivated')
        expect(response.body).not_to include('GL_ID')
        expect(response.media_type).not_to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
      end
    end

    context 'with invalid Shell JWT' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          { Gitlab::Shell::API_HEADER => 'invalid-jwt' }
        )
      end

      it 'returns not found' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with a Shell JWT signed with the wrong secret' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(
            secret_token: 'x' * 32,
            claims: { 'gl_id' => "user-#{user.id}", 'check_ip' => '1.2.3.4' }
          )
        )
      end

      it_behaves_like 'rejecting an unverified Shell JWT client IP'
    end

    context 'with a validly-signed Shell JWT from the wrong issuer' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(
            issuer: 'not-gitlab-shell',
            claims: { 'gl_id' => "user-#{user.id}", 'check_ip' => '1.2.3.4' }
          )
        )
      end

      it_behaves_like 'rejecting an unverified Shell JWT client IP'
    end

    context 'with Shell JWT but no gl_id claim' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header
        )
      end

      it 'returns not found' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with Shell JWT using deploy-token gl_id' do
      let_it_be(:deploy_token) { create(:deploy_token, :project, projects: [project]) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "deploy-token-#{deploy_token.id}" })
        )
      end

      it 'rejects deploy tokens for SSH endpoints' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'without Shell JWT header' do
      let(:headers) { workhorse_internal_api_request_header }

      it 'returns not found' do
        make_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'POST /ssh-upload-pack' do
    subject(:make_request) { post "/#{path}/ssh-upload-pack", headers: headers }

    context 'with valid Shell JWT including gl_id' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{user.id}" })
        )
      end

      it 'returns 200 with Workhorse Gitaly JSON', :aggregate_failures do
        expect(::Gitlab::GitAccessProject).to receive(:new).with(
          user,
          project,
          'ssh',
          hash_including(authentication_abilities: ::Gitlab::Auth.read_write_project_authentication_abilities)
        ).and_call_original

        make_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          'GL_ID' => "user-#{user.id}",
          'GL_REPOSITORY' => "project-#{project.id}",
          'GL_USERNAME' => user.username
        )
        expect(json_response).to have_key('NeedAudit')
      end
    end

    context 'with Shell JWT via key-based gl_id' do
      let_it_be(:key) { create(:personal_key, user: user) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "key-#{key.id}" })
        )
      end

      it 'resolves user from key and returns 200', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['GL_ID']).to eq("user-#{user.id}")
        expect(json_response['GL_USERNAME']).to eq(user.username)
        expect(json_response).to have_key('NeedAudit')
      end
    end

    it_behaves_like 'a shell-authenticated SSH-over-HTTP endpoint rejecting unauthenticated requests'
    it_behaves_like 'an SSH-over-HTTP endpoint honouring Shell JWT key and client IP claims'

    context 'with deploy key claims' do
      context 'with an ownerless deploy key that has access' do
        let_it_be(:deploy_key) { create(:deploy_key, readonly_access_to: project) }

        let(:headers) { shell_headers(deploy_key_claims(deploy_key)) }

        it 'checks access as the deploy key and returns its GL_ID', :aggregate_failures do
          expect(::Gitlab::GitAccessProject).to receive(:new).with(
            deploy_key, project, 'ssh', hash_including(authentication_abilities: anything)
          ).and_call_original

          make_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include(
            'GL_ID' => "key-#{deploy_key.id}",
            'GL_USERNAME' => deploy_key.user.username,
            'GL_REPOSITORY' => "project-#{project.id}"
          )
          expect(json_response.dig('GitalyServer', 'call_metadata', 'user_id')).to eq("user-#{deploy_key.user.id}")
        end
      end

      context 'with an owned deploy key whose owner cannot access the project' do
        using RSpec::Parameterized::TableSyntax

        let_it_be(:non_member) { create(:user) }
        let_it_be(:blocked_owner) { create(:user, :blocked) }
        let_it_be(:non_member_deploy_key) { create(:deploy_key, user: non_member, readonly_access_to: project) }
        let_it_be(:blocked_owner_deploy_key) { create(:deploy_key, user: blocked_owner, readonly_access_to: project) }

        where(:deploy_key) { [ref(:non_member_deploy_key), ref(:blocked_owner_deploy_key)] }

        with_them do
          let(:headers) { shell_headers(deploy_key_claims(deploy_key)) }

          it 'allows the pull', :aggregate_failures do
            make_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['GL_ID']).to eq("key-#{deploy_key.id}")
          end
        end
      end

      context 'with a deploy key not attached to the project' do
        let_it_be(:deploy_key) { create(:deploy_key, user: user) }

        let(:headers) { shell_headers(deploy_key_claims(deploy_key)) }

        it 'returns not found', :aggregate_failures do
          make_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(response.body).not_to include('GL_ID')
        end
      end
    end

    context 'when the enabled_git_access_protocol setting is ssh' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{user.id}" })
        )
      end

      before do
        stub_application_setting(enabled_git_access_protocol: 'ssh')
      end

      it 'authorizes the SSH-over-HTTP request' do
        make_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the enabled_git_access_protocol setting is http' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{user.id}" })
        )
      end

      before do
        stub_application_setting(enabled_git_access_protocol: 'http')
      end

      it 'rejects the SSH-over-HTTP request as an SSH protocol denial', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq('Git access over SSH is not allowed')
      end
    end

    context 'without Shell JWT header (only Workhorse header)' do
      let(:headers) { workhorse_internal_api_request_header }

      it 'returns not found for public and private projects', :aggregate_failures do
        post "/#{project.full_path}.git/ssh-upload-pack", headers: headers
        expect(response).to have_gitlab_http_status(:not_found)

        post "/#{public_project.full_path}.git/ssh-upload-pack", headers: headers
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'POST /ssh-receive-pack' do
    subject(:make_request) { post "/#{path}/ssh-receive-pack", headers: headers }

    context 'with valid Shell JWT including gl_id' do
      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{user.id}" })
        )
      end

      it 'returns 200 with Workhorse Gitaly JSON', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          'GL_ID' => "user-#{user.id}",
          'GL_REPOSITORY' => "project-#{project.id}",
          'GL_USERNAME' => user.username
        )
        expect(json_response).to have_key('NeedAudit')
      end
    end

    context 'with valid Shell JWT for a read-only member' do
      let_it_be(:read_only_user) { create(:user) }

      let(:headers) do
        workhorse_internal_api_request_header.merge(
          gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{read_only_user.id}" })
        )
      end

      before_all do
        project.add_guest(read_only_user)
      end

      it 'denies the push through GitAccess', :aggregate_failures do
        make_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(response.body).to eq('You are not allowed to push code to this project.')
      end
    end

    it_behaves_like 'a shell-authenticated SSH-over-HTTP endpoint rejecting unauthenticated requests'
    it_behaves_like 'an SSH-over-HTTP endpoint honouring Shell JWT key and client IP claims'

    context 'with deploy key claims' do
      context 'with a read-only deploy key' do
        let_it_be(:deploy_key) { create(:deploy_key, readonly_access_to: project) }

        let(:headers) { shell_headers(deploy_key_claims(deploy_key)) }

        it 'denies the push as the deploy key', :aggregate_failures do
          make_request

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(response.body).to eq('This deploy key does not have write access to this project.')
        end
      end

      context 'with a deploy key with write access' do
        let_it_be(:deploy_key) { create(:deploy_key, write_access_to: project) }

        let(:headers) { shell_headers(deploy_key_claims(deploy_key)) }

        it 'allows the push and returns the deploy key GL_ID', :aggregate_failures do
          make_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['GL_ID']).to eq("key-#{deploy_key.id}")
        end
      end
    end
  end

  describe 'Shell JWT isolation from standard Git endpoints' do
    let(:headers) do
      workhorse_internal_api_request_header.merge(
        gitlab_shell_internal_api_request_header(claims: { 'gl_id' => "user-#{user.id}" })
      )
    end

    it 'does not authenticate POST /git-upload-pack with a Shell JWT' do
      post "/#{path}/git-upload-pack", headers: headers

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it 'does not authenticate POST /git-receive-pack with a Shell JWT' do
      post "/#{path}/git-receive-pack", headers: headers

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it 'does not authenticate GET /info/refs with a Shell JWT' do
      get "/#{path}/info/refs", params: { service: 'git-upload-pack' }, headers: headers

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    context 'with deploy key and check_ip claims' do
      let_it_be(:deploy_key) { create(:deploy_key, write_access_to: project) }

      let(:headers) { shell_headers(deploy_key_claims(deploy_key).merge('check_ip' => '1.2.3.4')) }

      it 'does not authenticate the standard Git endpoints', :aggregate_failures do
        allow(::Gitlab::IpAddressState).to receive(:with).and_call_original
        expect(::Gitlab::IpAddressState).not_to receive(:with).with('1.2.3.4')

        post "/#{path}/git-upload-pack", headers: headers
        expect(response).to have_gitlab_http_status(:unauthorized)

        post "/#{path}/git-receive-pack", headers: headers
        expect(response).to have_gitlab_http_status(:unauthorized)

        get "/#{path}/info/refs", params: { service: 'git-upload-pack' }, headers: headers
        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end
  end
end
