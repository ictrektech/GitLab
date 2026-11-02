# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Groups::Settings::Orbit', feature_category: :knowledge_graph do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let(:requested_group) { group }

  before do
    sign_in(user)
    get group_settings_orbit_path(requested_group)
  end

  context 'when the user is an owner of a Free root group' do
    let(:user) { owner }

    it 'renders the page' do
      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'when the user is a maintainer' do
    let(:user) { maintainer }

    it 'returns not found' do
      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the group is a subgroup' do
    let(:user) { owner }
    let(:requested_group) { subgroup }

    it 'returns not found' do
      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
