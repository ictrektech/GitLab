# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ContainerRegistry::Client do
  let(:token) { '12345' }
  let(:options) { { token: token } }
  let(:client) { described_class.new("http://registry", options) }
  let(:base_headers) { { 'Authorization' => 'bearer 12345', 'User-Agent' => "GitLab/#{Gitlab::VERSION}" } }
  let(:accept_header) { ContainerRegistry::Client::ACCEPTED_TYPES.join(', ') }

  let(:headers_with_accept_types) do
    base_headers.merge({ 'Accept' => accept_header })
  end

  describe '#push_blob' do
    it 'follows redirect and makes put query' do
      stub_request(:put, "http://registry/v2/group/test/blobs/uploads/abcd?digest=mytag")
        .with(headers: base_headers)
        .to_return(status: 200, body: '', headers: { 'Content-Length' => '5' })

      stub_request(:post, "http://registry/v2/group/test/blobs/uploads/")
        .with(headers: base_headers)
        .to_return(status: 200, body: '', headers: { 'Location' => 'http://registry/v2/group/test/blobs/uploads/abcd' })

      expect(client.push_blob('group/test', 'mytag', '', 5)).to be(true)
    end

    it 'raises error if response status is not 200' do
      stub_request(:put, "http://registry/v2/group/test/blobs/uploads/abcd?digest=mytag")
        .with(headers: base_headers)
        .to_return(status: 404, body: "", headers: {})

      stub_request(:post, "http://registry/v2/group/test/blobs/uploads/")
        .with(headers: base_headers)
        .to_return(status: 200, body: "", headers: { 'Location' => 'http://registry/v2/group/test/blobs/uploads/abcd' })

      expect { client.push_blob('group/test', 'mytag', '', 32456) }
        .to raise_error(EE::ContainerRegistry::Client::Error)
    end
  end

  describe '#push_manifest' do
    let(:manifest) { 'manifest' }
    let(:manifest_type) { 'application/vnd.docker.distribution.manifest.v2+json' }
    let(:manifest_headers) do
      base_headers.merge({
        'Accept' => accept_header,
        'Content-Type' => 'application/vnd.docker.distribution.manifest.v2+json'
      })
    end

    it 'PUT v2/:name/manifests/:tag' do
      stub_request(:put, "http://registry/v2/group/test/manifests/my-tag")
        .with(
          body: "manifest",
          headers: manifest_headers
        )
        .to_return(status: 200, body: "", headers: {})

      expect(client.push_manifest('group/test', 'my-tag', manifest, manifest_type)).to be(true)
    end

    it 'raises error if response status is not 200' do
      stub_request(:put, "http://registry/v2/group/test/manifests/my-tag")
        .with(
          body: "manifest",
          headers: manifest_headers
        )
        .to_return(status: 404, body: "", headers: {})

      expect { client.push_manifest('group/test', 'my-tag', manifest, manifest_type) }
        .to raise_error(EE::ContainerRegistry::Client::Error)
    end
  end

  describe '#blob_exists?' do
    let(:digest) { 'digest' }

    it 'returns true' do
      stub_request(:head, "http://registry/v2/group/test/blobs/digest")
        .with(headers: headers_with_accept_types)
        .to_return(status: 200, body: "", headers: {})

      expect(client.blob_exists?('group/test', digest)).to be(true)
    end

    it 'returns false' do
      stub_request(:head, "http://registry/v2/group/test/blobs/digest")
        .with(headers: headers_with_accept_types)
        .to_return(status: 404, body: "", headers: {})

      expect(client.blob_exists?('group/test', digest)).to be(false)
    end
  end

  describe '#manifest_exists?' do
    let(:reference) { 'sha256:abc123' }

    it 'returns true' do
      stub_request(:head, "http://registry/v2/group/test/manifests/sha256:abc123")
        .with(headers: headers_with_accept_types)
        .to_return(status: 200, body: "", headers: {})

      expect(client.manifest_exists?('group/test', reference)).to be(true)
    end

    it 'returns false' do
      stub_request(:head, "http://registry/v2/group/test/manifests/sha256:abc123")
        .with(headers: headers_with_accept_types)
        .to_return(status: 404, body: "", headers: {})

      expect(client.manifest_exists?('group/test', reference)).to be(false)
    end
  end

  describe '#repository_raw_manifest' do
    let(:manifest) { '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","layers":[]}' }

    it 'GET "/v2/:name/manifests/:reference returns the byte-exact manifest body' do
      stub_request(:get, 'http://registry/v2/group/test/manifests/my-tag')
        .with(headers: headers_with_accept_types)
        .to_return(
          status: 200,
          body: manifest,
          headers: { 'Content-Type' => 'application/vnd.oci.image.manifest.v1+json' }
        )

      result = client.repository_raw_manifest('group/test', 'my-tag')

      expect(result).to eq(manifest)
    end

    it 'raises error' do
      stub_request(:get, 'http://registry/v2/group/test/manifests/my-tag')
        .with(headers: headers_with_accept_types)
        .to_return(status: 500, body: 'Something is wrong', headers: {})

      expect { client.repository_raw_manifest('group/test', 'my-tag') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /500 - Something is wrong/)
    end

    it 'raises NotFoundError when the manifest does not exist' do
      stub_request(:get, 'http://registry/v2/group/test/manifests/my-tag')
        .with(headers: headers_with_accept_types)
        .to_return(status: 404, body: 'Not found', headers: {})

      expect { client.repository_raw_manifest('group/test', 'my-tag') }
        .to raise_error(EE::ContainerRegistry::Client::NotFoundError, /404 - Not found/)
    end
  end

  describe '#pull_blob' do
    before do
      stub_request(:get, "http://registry/v2/group/test/blobs/e2312abc")
          .with(headers: base_headers)
          .to_return(status: 302, headers: { 'Location' => 'http://download-link.com' })
    end

    it 'downloads file successfully when' do
      stub_request(:get, "http://download-link.com/")
        .to_return(status: 200, headers: { 'Content-Length' => '32456' })

      # With this stub we assert that there is no Authorization header in the request.
      # This also mimics the real case because Amazon s3 returns error too.
      stub_request(:get, "http://download-link.com/")
        .with(headers: base_headers)
        .to_return(status: 500)

      enumerator, size = client.pull_blob('group/test', 'e2312abc')

      expect(enumerator).to be_a_kind_of(HTTP::Response::Body)
      expect(size).to eq(32456)
    end

    it 'raises error when it can not download blob' do
      stub_request(:get, "http://download-link.com/")
        .to_return(status: 500, body: 'Something is wrong')

      expect { client.pull_blob('group/test', 'e2312abc') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /500 - Something is wrong/)
    end

    it 'raises error when request is not authenticated' do
      stub_request(:get, "http://registry/v2/group/test/blobs/e2312abc")
          .with(headers: base_headers)
          .to_return(status: 401, body: 'Something is wrong')

      expect { client.pull_blob('group/test', 'e2312abc') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /401 - Something is wrong/)
    end

    context 'when primary_api_url is specified with trailing slash' do
      let(:client) { described_class.new("http://registry/", options) }

      it 'builds correct URL' do
        stub_request(:get, "http://registry//v2/group/test/blobs/e2312abc")
          .with(headers: base_headers)
          .to_return(status: 500)

        stub_request(:get, "http://download-link.com/")
          .to_return(status: 200, headers: { 'Content-Length' => '32456' })

        enumerator, size = client.pull_blob('group/test', 'e2312abc')

        expect(enumerator).to be_a_kind_of(HTTP::Response::Body)
        expect(size).to eq(32456)
      end
    end

    context 'direct link to download, no redirect' do
      it 'downloads blob successfully' do
        stub_request(:get, "http://registry/v2/group/test/blobs/e2312abc")
            .with(headers: base_headers)
            .to_return(status: 200, headers: { 'Content-Length' => '32456' })

        enumerator, size = client.pull_blob('group/test', 'e2312abc')

        expect(enumerator).to be_a_kind_of(HTTP::Response::Body)
        expect(size).to eq(32456)
      end
    end
  end

  describe '#repository_tag_names' do
    let(:page_size) { ContainerRegistry::Client::DEFAULT_TAGS_PAGE_SIZE }
    let(:tags_url) { 'http://registry/v2/group/test/tags/list' }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }
    let(:next_link) { { 'Link' => '</v2/group/test/tags/list?n=10000&last=tag-b>; rel="next"' } }

    def stub_tags_page(query, status: 200, body: nil, headers: {})
      stub_request(:get, tags_url)
        .with(query: query, headers: base_headers)
        .to_return(status: status, body: body, headers: json_headers.merge(headers))
    end

    it 'returns the tags of a single page without a Link header' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]))

      expect(client.repository_tag_names('group/test')).to eq(%w[tag-a tag-b])
    end

    it 'follows the Link header using the last tag of the previous page', :aggregate_failures do
      first_page = stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      second_page = stub_tags_page({ n: page_size, last: 'tag-b' }, body: Gitlab::Json.dump(tags: %w[tag-c tag-d]))

      expect(client.repository_tag_names('group/test')).to eq(%w[tag-a tag-b tag-c tag-d])
      expect(first_page).to have_been_requested.once
      expect(second_page).to have_been_requested.once
    end

    it 'returns an empty array when the repository is not found' do
      stub_tags_page({ n: page_size }, status: 404, body: Gitlab::Json.dump(errors: [{ code: 'NAME_UNKNOWN' }]))

      expect(client.repository_tag_names('group/test')).to eq([])
    end

    it 'raises when the first page fails' do
      stub_tags_page({ n: page_size }, status: 500, body: Gitlab::Json.dump(errors: [{ code: 'UNKNOWN' }]))

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /List tags error: 500/)
    end

    it 'raises instead of returning a partial list when a later page fails' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      stub_tags_page({ n: page_size, last: 'tag-b' }, status: 500,
        body: Gitlab::Json.dump(errors: [{ code: 'UNKNOWN' }]))

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /List tags error: 500/)
    end

    it 'raises instead of returning an empty list when a later page returns 404' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      stub_tags_page({ n: page_size, last: 'tag-b' }, status: 404,
        body: Gitlab::Json.dump(errors: [{ code: 'NAME_UNKNOWN' }]))

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /List tags error: 404/)
    end

    it 'raises when a successful response is not JSON' do
      stub_tags_page({ n: page_size }, body: '<html>tags</html>', headers: { 'Content-Type' => 'text/html' })

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /unexpected response body/)
    end

    it 'returns an empty array when tags is null' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(name: 'group/test', tags: nil))

      expect(client.repository_tag_names('group/test')).to eq([])
    end

    it 'returns an empty array when the tags key is missing' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(name: 'group/test'))

      expect(client.repository_tag_names('group/test')).to eq([])
    end

    where(:tags_value) do
      [['oops'], [false], [true], [1], [{ 'a' => 1 }], [[1, 2]], [['tag-a', nil]]]
    end

    with_them do
      it 'raises when tags is not an array of strings' do
        stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: tags_value))

        expect { client.repository_tag_names('group/test') }
          .to raise_error(EE::ContainerRegistry::Client::Error, /unexpected tags value/)
      end
    end

    it 'raises when an empty page advertises a next page' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: []), headers: next_link)

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /next page advertised after an empty page/)
    end

    it 'returns the earlier tags when the last page is empty and has no Link header' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      stub_tags_page({ n: page_size, last: 'tag-b' }, body: Gitlab::Json.dump(tags: []))

      expect(client.repository_tag_names('group/test')).to eq(%w[tag-a tag-b])
    end

    it 'raises when a later empty page still advertises a next page' do
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      stub_tags_page({ n: page_size, last: 'tag-b' }, body: Gitlab::Json.dump(tags: []), headers: next_link)

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /next page advertised after an empty page/)
    end

    it 'raises when the page cap is exceeded' do
      stub_const('EE::ContainerRegistry::Client::MAX_TAG_PAGES', 2)
      stub_tags_page({ n: page_size }, body: Gitlab::Json.dump(tags: %w[tag-a tag-b]), headers: next_link)
      stub_tags_page({ n: page_size, last: 'tag-b' }, body: Gitlab::Json.dump(tags: %w[tag-c tag-d]),
        headers: { 'Link' => '</v2/group/test/tags/list?n=10000&last=tag-d>; rel="next"' })

      expect { client.repository_tag_names('group/test') }
        .to raise_error(EE::ContainerRegistry::Client::Error, /more than 2 pages/)
    end
  end
end
