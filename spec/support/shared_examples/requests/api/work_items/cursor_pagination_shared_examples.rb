# frozen_string_literal: true

# Requires `api_request_path` and `user`. The collection must hold between two and 100 records (`all_ids` is read
# with the maximum `per_page`), and every record on the first page must be readable by `user`: pagination runs
# before the policy filter, so an unreadable record there shortens the page and breaks the
# `all_ids.first(page_size)` comparison.
RSpec.shared_examples 'a work item endpoint paginated by cursor' do
  let(:all_ids) do
    get api(api_request_path, user), params: { per_page: 100 }
    json_response.pluck('id')
  end

  let(:page_size) { all_ids.size - 1 }

  it 'pages through the collection with cursor headers and emits no offset headers' do
    expect(all_ids.size).to be >= 2

    get api(api_request_path, user), params: { per_page: page_size }

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.pluck('id')).to eq(all_ids.first(page_size))
    expect(response.headers['X-Next-Cursor']).to be_present
    expect(response.headers['Link']).to include(%(cursor=#{CGI.escape(response.headers['X-Next-Cursor'])}),
      'rel="next"')
    expect(response.headers).not_to include('X-Total', 'X-Total-Pages', 'X-Page', 'X-Next-Page', 'X-Prev-Page',
      'X-Per-Page')

    get api(api_request_path, user), params: { per_page: page_size, cursor: response.headers['X-Next-Cursor'] }

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.pluck('id')).to eq(all_ids.last(1))
    expect(response.headers['X-Prev-Cursor']).to be_present
    expect(response.headers['X-Next-Cursor']).to be_nil
    expect(response.headers['Link']).to be_nil
  end

  it 'ignores the page parameter' do
    get api(api_request_path, user), params: { per_page: page_size, page: 2 }

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.pluck('id')).to eq(all_ids.first(page_size))
  end

  it_behaves_like 'a work item endpoint guarding cursor pagination params'
end

# Requires `api_request_path` and `user`. Split out so collections that never fill two pages, such as
# linked resources, still cover the parameter checks.
RSpec.shared_examples 'a work item endpoint guarding cursor pagination params' do
  it 'returns 400 when the cursor cannot be used' do
    [
      'not-base64!!',
      Base64.urlsafe_encode64('{'),
      Base64.urlsafe_encode64('20'),
      Base64.urlsafe_encode64('[1]'),
      Base64.urlsafe_encode64({ unexpected: 1, _kd: 'n' }.to_json),
      Base64.urlsafe_encode64({ id: 10**30, _kd: 'n' }.to_json),
      Base64.urlsafe_encode64({ id: (10**30).to_s, _kd: 'n' }.to_json),
      Base64.urlsafe_encode64({ id: [1], _kd: 'n' }.to_json)
    ].each do |cursor|
      get api(api_request_path, user), params: { cursor: cursor }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['error']).to include('cursor')
    end
  end

  it 'returns 400 when per_page is outside 1..100' do
    [0, -1, 101].each do |per_page|
      get api(api_request_path, user), params: { per_page: per_page }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['error']).to include('per_page')
    end
  end

  it 'returns 405 when offset pagination is requested explicitly' do
    get api(api_request_path, user), params: { pagination: 'offset' }

    expect(response).to have_gitlab_http_status(:method_not_allowed)
    expect(json_response['error']).to include('offset pagination is not supported')
  end
end

# Requires `api_request_path`, `user` and `unreadable_record_id`: a record in the collection that `user` cannot
# read and that does not sort last. Pagination runs before the policy filter, so the page holding that record
# comes back short (empty at `per_page` 1) but must still carry `X-Next-Cursor`, or a client loses its place.
RSpec.shared_examples 'a work item endpoint keeping the cursor on a short page' do
  it 'returns an empty page for the unreadable record and still advances the cursor' do
    get api(api_request_path, user), params: { per_page: 100 }

    readable_ids = json_response.pluck('id')
    expect(readable_ids).not_to include(unreadable_record_id)

    pages = []
    cursor = nil

    loop do
      get api(api_request_path, user), params: { per_page: 1, cursor: cursor }.compact

      expect(response).to have_gitlab_http_status(:ok)
      pages << json_response.pluck('id')
      cursor = response.headers['X-Next-Cursor']

      break if cursor.nil? || pages.size > readable_ids.size + 2
    end

    expect(pages.flatten).to eq(readable_ids)
    # An empty page before the last one means the unreadable record's page still carried a next cursor.
    expect(pages[0...-1]).to include([])
  end
end

# `segment` is the last path segment of the list route, for example 'children'. Matching on it keeps
# single-record routes such as `notes/:note_id` out of the check.
RSpec.shared_examples 'work item list routes declaring cursor pagination' do |segment|
  it "declares cursor and not page on the #{segment} list routes" do
    routes = described_class.routes.select do |route|
      route.request_method == 'GET' && route.path.end_with?("/#{segment}(.:format)")
    end

    expect(routes).to be_present
    routes.each do |route|
      expect(route.params.keys).to include('cursor', 'per_page')
      expect(route.params.keys).not_to include('page')
    end
  end
end
