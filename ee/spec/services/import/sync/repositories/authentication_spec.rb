# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::Authentication, feature_category: :importers do
  let_it_be_with_reload(:project) do
    create(:project, :import_started, import_type: 'github', import_url: 'https://github.com/octocat/hello-world.git')
  end

  let_it_be_with_reload(:repository) do
    create(:import_sync_repository, :oauth, project: project, provider_full_name: 'octocat/hello-world')
  end

  subject(:authentication) { described_class.for(repository) }

  before do
    project.import_data&.destroy!
    project.reload.create_import_data!(credentials: { user: 'oauth-token' })
  end

  describe '#client' do
    it 'builds a client with the OAuth token from the import data' do
      expect(Gitlab::GithubImport::Client).to receive(:new)
        .with('oauth-token', hash_including(parallel: false))
        .and_call_original

      expect(authentication.client(parallel: false)).to be_a(Gitlab::GithubImport::Client)
    end

    it 'defaults to a parallel client' do
      expect(Gitlab::GithubImport::Client).to receive(:new)
        .with('oauth-token', hash_including(parallel: true))
        .and_call_original

      authentication.client
    end
  end

  describe '#repository_url' do
    it 'derives a credential-free URL from the provider identity' do
      expect(authentication.repository_url).to eq('https://github.com/octocat/hello-world.git')
    end

    it 'does not append .git twice' do
      repository.provider_full_name = 'octocat/hello-world.git'

      expect(described_class.for(repository).repository_url).to eq('https://github.com/octocat/hello-world.git')
    end

    it 'falls back to github.com when the project has no import URL' do
      project.update_column(:import_url, nil)

      expect(described_class.for(repository).repository_url).to eq('https://github.com/octocat/hello-world.git')
    end

    it 'uses the host of the import URL for GitHub Enterprise' do
      project.update_column(:import_url, 'https://user:secret@ghe.example.com:8443/octocat/hello-world.git')

      expect(described_class.for(repository).repository_url)
        .to eq('https://ghe.example.com:8443/octocat/hello-world.git')
    end

    it 'rejects a malformed provider identity' do
      %w[octocat octocat/../x a/b/c octocat/hello?world].each do |name|
        repository.provider_full_name = name

        expect { described_class.for(repository).repository_url }
          .to raise_error(Import::Sync::Errors::ProviderIdentityError)
      end
    end
  end

  describe '#resolved_address' do
    let(:clone_url) { 'https://github.com/octocat/hello-world.git' }

    it 'checks the clone URL with the instance settings and returns the address that passed' do
      stub_application_setting(dns_rebinding_protection_enabled: true, deny_all_requests_except_allowed: true)
      allow(Gitlab::HTTP_V2::UrlBlocker).to receive(:validate!)
        .and_return([URI.parse('https://140.82.112.3/octocat/hello-world.git'), 'github.com'])

      expect(authentication.resolved_address).to eq('140.82.112.3')
      expect(Gitlab::HTTP_V2::UrlBlocker).to have_received(:validate!).with(
        clone_url,
        hash_including(
          schemes: Project::VALID_IMPORT_PROTOCOLS,
          ports: Project::VALID_IMPORT_PORTS,
          dns_rebind_protection: true,
          deny_all_requests_except_allowed: true
        )
      )
    end

    it 'leaves DNS rebinding protection off behind an HTTP proxy' do
      stub_application_setting(dns_rebinding_protection_enabled: true)
      allow(Gitlab).to receive(:http_proxy_env?).and_return(true)
      allow(Gitlab::HTTP_V2::UrlBlocker).to receive(:validate!).and_return([URI.parse(clone_url), 'github.com'])

      authentication.resolved_address

      expect(Gitlab::HTTP_V2::UrlBlocker).to have_received(:validate!)
        .with(clone_url, hash_including(dns_rebind_protection: false))
    end

    it 'returns an empty address when the host was not resolved' do
      allow(Gitlab::HTTP_V2::UrlBlocker).to receive(:validate!).and_return([URI.parse(clone_url), nil])

      expect(authentication.resolved_address).to eq('')
    end

    it 'raises when the clone URL is blocked' do
      allow(Gitlab::HTTP_V2::UrlBlocker).to receive(:validate!)
        .and_raise(Gitlab::HTTP_V2::UrlBlocker::BlockedUrlError, 'Requests to localhost are not allowed')

      expect { authentication.resolved_address }
        .to raise_error(Gitlab::HTTP_V2::UrlBlocker::BlockedUrlError, 'Requests to localhost are not allowed')
    end
  end

  describe '.valid_full_name?' do
    it 'accepts owner/name and rejects anything else' do
      expect(described_class.valid_full_name?('octocat/hello-world.git')).to be(true)
      expect(described_class.valid_full_name?(nil)).to be(false)

      %w[octocat octocat/../x a/b/c octocat/hello?world].each do |name|
        expect(described_class.valid_full_name?(name)).to be(false)
      end
    end
  end

  describe '#http_authorization_header' do
    it 'returns a Basic header carrying the token' do
      expect(authentication.http_authorization_header)
        .to eq("Basic #{Base64.strict_encode64('x-access-token:oauth-token')}")
    end
  end

  describe '#inspect' do
    it 'does not expose the token' do
      authentication.http_authorization_header

      expect(authentication.inspect).not_to include('oauth-token')
    end
  end

  context 'with an expiring OAuth token', :freeze_time do
    let(:expires_at) { 1.hour.from_now.to_i }
    let(:token_url) { 'https://github.com/login/oauth/access_token' }
    let(:config) do
      Gitlab::Configs::Options.build(
        'app_id' => 'app-id',
        'app_secret' => 'app-secret',
        'args' => { 'client_options' => { 'site' => 'https://api.github.com', 'token_url' => token_url } }
      )
    end

    before do
      project.import_data.update!(credentials: { user: 'ghu_old', refresh_token: 'ghr_old', expires_at: expires_at })
      allow(Gitlab::Auth::OAuth::Provider).to receive(:config_for).with('github').and_return(config)
      stub_request(:post, token_url).to_return(
        status: 200,
        body: { access_token: 'ghu_new', refresh_token: 'ghr_new', expires_in: 28800 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    it 'gives the API client and the Gitaly header the refreshed token after a 401' do
      stub_request(:get, 'https://api.github.com/repos/octocat/hello-world')
        .with(headers: { 'Authorization' => /ghu_old/ })
        .to_return(status: 401)
      stub_request(:get, 'https://api.github.com/repos/octocat/hello-world')
        .with(headers: { 'Authorization' => /ghu_new/ })
        .to_return(status: 200, body: { id: 1 }.to_json, headers: { 'Content-Type' => 'application/json' })

      client = authentication.client
      allow(client).to receive(:requests_remaining?).and_return(true)

      expect(client.repository('octocat/hello-world')).to include(id: 1)
      expect(authentication.http_authorization_header)
        .to eq("Basic #{Base64.strict_encode64('x-access-token:ghu_new')}")
    end

    context 'when the token is about to expire' do
      let(:expires_at) { 1.minute.from_now.to_i }

      it 'refreshes it before the client or the header uses it' do
        expect(Gitlab::GithubImport::Client).to receive(:new)
          .with('ghu_new', hash_including(token_refresher: an_instance_of(Proc)))

        authentication.client

        expect(authentication.http_authorization_header)
          .to eq("Basic #{Base64.strict_encode64('x-access-token:ghu_new')}")
      end
    end
  end

  context 'when the project has no import data' do
    before do
      project.import_data.destroy!
      project.reload
    end

    it 'raises for the client and the header' do
      expect { authentication.client }.to raise_error(Import::Sync::Errors::MissingCredentialsError)
      expect { authentication.http_authorization_header }
        .to raise_error(Import::Sync::Errors::MissingCredentialsError)
    end
  end

  context 'when the import data has no token' do
    before do
      project.import_data.update!(credentials: {})
      project.reload
    end

    it 'raises MissingCredentialsError' do
      expect { authentication.client }.to raise_error(Import::Sync::Errors::MissingCredentialsError)
    end
  end

  context 'when the import data has no credentials at all' do
    before do
      project.import_data.update!(credentials: nil)
      project.reload
    end

    it 'raises MissingCredentialsError' do
      expect { authentication.client }.to raise_error(Import::Sync::Errors::MissingCredentialsError)
    end
  end
end
