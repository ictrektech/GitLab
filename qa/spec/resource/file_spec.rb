# frozen_string_literal: true

RSpec.describe QA::Resource::File do
  include QA::Support::Helpers::StubEnv

  subject(:file) { described_class.new }

  let(:project) do
    instance_double(QA::Resource::Project,
      default_branch: 'main', path_with_namespace: 'group/project', full_path: 'group/project')
  end

  before do
    allow(QA::Resource::Project).to receive(:fabricate!).and_return(project)
  end

  describe '#query_parameters' do
    it 'includes the default branch as ref' do
      expect(file.query_parameters).to eq({ ref: 'main' })
    end

    it 'includes the escaped custom branch as ref' do
      file.branch = 'feature/new#file'

      expect(file.query_parameters).to eq({ ref: 'feature%2Fnew%23file' })
    end
  end

  describe '#fabricate_via_api!' do
    let(:api_client) { instance_double(QA::Runtime::API::Client) }
    let(:file_path) { '/projects/group%2Fproject/repository/files/second' }
    let(:raw_post) { instance_double(RestClient::Response, code: 201, body: { file_path: 'second' }.to_json) }
    let(:raw_get) { instance_double(RestClient::Response, code: 200, body: {}.to_json) }

    before do
      QA::Runtime::Scenario.define(:gitlab_address, 'https://gitlab.example.com')
      file.api_client = api_client
      file.name = 'second'

      allow(QA::Runtime::API::Request).to receive(:new) do |_client, path|
        instance_double(QA::Runtime::API::Request, url: "https://gitlab.example.com/api/v4#{path}")
      end
      allow(file).to receive_messages(post: raw_post, get: raw_get)
    end

    shared_examples 'sends ref only when checking availability' do
      it 'creates the file without ref and checks availability with ref' do
        file.fabricate_via_api!

        expect(QA::Runtime::API::Request).to have_received(:new).with(api_client, file_path)
        expect(QA::Runtime::API::Request).to have_received(:new).with(api_client, "#{file_path}?ref=main")
        expect(file).to have_received(:post).with("https://gitlab.example.com/api/v4#{file_path}", anything, {})
      end
    end

    context 'when not running against a Cell' do
      it_behaves_like 'sends ref only when checking availability'
    end

    context 'when running against a Cell' do
      before do
        stub_env('QA_COOKIES', '_gitlab_session=cell-9-please')
      end

      it_behaves_like 'sends ref only when checking availability'
    end
  end
end
