# frozen_string_literal: true

RSpec.shared_examples 'status board list' do
  let(:system_defined_status) { build(:work_item_system_defined_status) }

  before do
    stub_licensed_features(board_status_lists: true, work_item_status: true)
  end

  context 'when status_id is sent' do
    it 'returns 400 if status is not found' do
      post api(url, user), params: { status_id: non_existing_record_id }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response.dig('message', 'error')).to eq('Status not found')
    end

    it 'returns 400 if not licensed' do
      stub_licensed_features(board_status_lists: false, work_item_status: false)

      post api(url, user), params: { status_id: system_defined_status.id }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response.dig('message', 'error'))
        .to eq('Status lists not available with your current license')
    end

    it 'creates a status list if status is found' do
      post api(url, user), params: { status_id: system_defined_status.id }

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response.dig('status', 'id')).to eq(system_defined_status.id)
      expect(json_response.dig('status', 'name')).to eq(system_defined_status.name)
    end

    it 'returns the status for an existing status list' do
      post api(url, user), params: { status_id: system_defined_status.id }

      get api(url, user)

      expect(response).to have_gitlab_http_status(:ok)
      status_list = json_response.find { |list| list.dig('status', 'id') == system_defined_status.id }
      expect(status_list).to be_present
      expect(status_list.dig('status', 'name')).to eq(system_defined_status.name)
    end

    context 'with custom status' do
      let_it_be(:custom_status) do
        create(:work_item_custom_status, namespace: board_parent.root_ancestor)
      end

      it 'creates a status list if custom status is found' do
        post api(url, user), params: { status_id: custom_status.id }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response.dig('status', 'id')).to eq(custom_status.id)
        expect(json_response.dig('status', 'name')).to eq(custom_status.name)
      end

      it 'creates a status list if a non-converted custom status is found' do
        non_converted_status = create(
          :work_item_custom_status, :without_conversion_mapping,
          namespace: board_parent.root_ancestor
        )

        post api(url, user), params: { status_id: non_converted_status.id }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response.dig('status', 'id')).to eq(non_converted_status.id)
        expect(json_response.dig('status', 'name')).to eq(non_converted_status.name)
      end

      it 'returns 400 if custom status is not found' do
        post api(url, user), params: { status_id: non_existing_record_id }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response.dig('message', 'error')).to eq('Status not found')
      end
    end
  end

  it 'returns 400 if no list type parameter is provided' do
    post api(url, user)

    expect(response).to have_gitlab_http_status(:bad_request)
    expect(json_response['error']).to eq(
      'label_id, milestone_id, iteration_id, assignee_id, status_id are missing, ' \
        'exactly one parameter must be provided'
    )
  end

  it 'returns 400 if more than one list type parameter is provided' do
    post api(url, user), params: { label_id: non_existing_record_id, status_id: system_defined_status.id }

    expect(response).to have_gitlab_http_status(:bad_request)
    expect(json_response['error']).to match(/are mutually exclusive/)
  end
end
