# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReconcileLfsObjectsService, feature_category: :importers do
  include StubRequests

  let_it_be_with_reload(:project) { create(:project, import_url: 'https://github.com/example/old-name.git') }

  let(:batch_url) { 'https://github.com/example/renamed.git/info/lfs/objects/batch' }
  let(:authentication) do
    instance_double(
      Import::Sync::Repositories::Authentication,
      repository_url: 'https://github.com/example/renamed.git',
      http_authorization_header: 'Basic secret-token'
    )
  end

  let(:lease_context) { instance_double(Import::Sync::Repositories::ApplicationLease::Context, renew!: true) }
  let(:contents) { %w[first-object second-object third-object] }
  let(:lfs_changes) { instance_double(Gitlab::Git::LfsChanges) }

  subject(:service) do
    described_class.new(project, authentication: authentication, lease_context: lease_context)
  end

  before_all do
    ApplicationSetting.create_from_defaults
  end

  before do
    stub_application_setting(allow_local_requests_from_web_hooks_and_services: false)
    allow(project).to receive(:lfs_enabled?).and_return(true)
    allow(project.repository).to receive(:lfsconfig_for).and_return(nil)
    allow(Gitlab::Git::LfsChanges).to receive(:new).with(project.repository).and_return(lfs_changes)
    allow(lfs_changes).to receive(:all_pointers) { pointers }

    stub_full_request(batch_url, method: :post)
      .with(headers: { 'Authorization' => 'Basic secret-token' })
      .to_return { |request| batch_response(request) }

    contents.each do |content|
      stub_full_request(download_url(content)).to_return(body: content)
    end
  end

  def pointers
    contents.map do |content|
      instance_double(Gitlab::Git::Blob, lfs_oid: oid(content), lfs_size: content.bytesize)
    end
  end

  def oid(content)
    Digest::SHA256.hexdigest(content)
  end

  def download_url(content)
    "https://objects.example.com/#{oid(content)}?signature=signed"
  end

  def batch_response(request)
    requested = Gitlab::Json::SafeParser.parse(request.body)['objects']
    objects = requested.map do |object|
      content = contents.find { |item| oid(item) == object['oid'] }

      object.merge('actions' => { 'download' => { 'href' => download_url(content) } })
    end

    { status: 200, body: Gitlab::Json.dump(objects: objects) }
  end

  it 'downloads every missing object from the current repository path and renews the lease after each one' do
    expect(service.execute).to be(true)

    expect(project.lfs_objects.pluck(:oid)).to match_array(contents.map { |content| oid(content) })
    expect(lease_context).to have_received(:renew!).exactly(3).times
  end

  it 'does not send the token when the batch endpoint is outside the repository origin' do
    allow(project.repository).to receive(:lfsconfig_for)
      .and_return("[lfs]\n\turl = https://lfs.example.com/example/renamed.git/info/lfs")

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError)

    expect(a_request(:post, /./)).not_to have_been_made
    expect(project.reload[:lfs_enabled]).not_to be(false)
  end

  context 'when more objects are missing than fit in one page' do
    before do
      stub_const("#{described_class}::MAX_OBJECTS_PER_PASS", 2)
      stub_const("#{Projects::LfsPointers::LfsDownloadLinkListService}::REQUEST_BATCH_SIZE", 2)
    end

    it 'returns false after one page and downloads the rest on the next pass' do
      expect(service.execute).to be(false)
      expect(project.lfs_objects.count).to eq(2)
      expect(a_request(:post, stubbed_hostname(batch_url))).to have_been_made.once

      expect(described_class.new(project, authentication: authentication, lease_context: lease_context).execute)
        .to be(true)
      expect(project.lfs_objects.pluck(:oid)).to match_array(contents.map { |content| oid(content) })
    end
  end

  it 'finishes a failed pass by requesting only the objects that are still missing' do
    stub_full_request(download_url(contents.last)).to_return(status: 500).then.to_return(body: contents.last)

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError)
    expect(project.lfs_objects.count).to eq(2)

    expect(described_class.new(project, authentication: authentication, lease_context: lease_context).execute)
      .to be(true)

    single_object_batch = a_request(:post, stubbed_hostname(batch_url)).with do |request|
      Gitlab::Json::SafeParser.parse(request.body)['objects'].size == 1
    end

    expect(project.lfs_objects.count).to eq(3)
    expect(single_object_batch).to have_been_made.once
  end

  it 'raises a fixed error without a cause when a download returns an error result', :aggregate_failures do
    allow_next_instance_of(Projects::LfsPointers::LfsDownloadService) do |download_service|
      allow(download_service).to receive(:execute)
        .and_return(status: :error, message: "couldn't be downloaded from #{download_url(contents.first)}")
    end

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError) do |error|
      expect(error.message).to eq('GitHub LFS update failed')
      expect(error.cause).to be_nil
    end
  end

  it 'raises a fixed error when a download returns no result' do
    allow_next_instance_of(Projects::LfsPointers::LfsDownloadService) do |download_service|
      allow(download_service).to receive(:execute).and_return(nil)
    end

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError, 'GitHub LFS update failed')
  end

  it 'raises a fixed error without a cause when discovery fails', :aggregate_failures do
    stub_full_request(batch_url, method: :post).to_return(status: 500, body: 'provider detail')

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError) do |error|
      expect(error.message).to eq('GitHub LFS update failed')
      expect(error.cause).to be_nil
    end
  end

  it 'raises a fixed error without a cause when listing pointers raises a gRPC call error', :aggregate_failures do
    allow(lfs_changes).to receive(:all_pointers).and_raise(GRPC::Core::CallError, 'provider detail')

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError) do |error|
      expect(error.message).to eq('GitHub LFS update failed')
      expect(error.cause).to be_nil
    end
  end

  it 'does not wrap a lost lease' do
    allow(lease_context).to receive(:renew!).and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

    expect { service.execute }.to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
  end

  where(
    error_class: [
      Import::Sync::Errors::MissingCredentialsError,
      Import::Github::RefreshOauthTokenService::BadRefreshTokenError
    ]
  )

  with_them do
    it 'does not wrap a credentials error, so the worker can disconnect the repository' do
      allow(authentication).to receive(:http_authorization_header).and_raise(error_class)

      expect { service.execute }.to raise_error(error_class)
    end
  end
end
