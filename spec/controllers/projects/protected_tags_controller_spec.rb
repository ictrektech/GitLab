# frozen_string_literal: true

require('spec_helper')

RSpec.describe Projects::ProtectedTagsController do
  describe "GET #index" do
    let(:project) { create(:project_empty_repo, :public) }

    it "redirects empty repo to projects page" do
      get(:index, params: { namespace_id: project.namespace.to_param, project_id: project })
    end
  end

  describe "GET #show" do
    let_it_be_with_reload(:project) { create(:project, :repository) }
    let(:user) { create(:user, maintainer_of: project) }
    let(:protected_tag) { create(:protected_tag, project: project, name: 'v*') }

    before do
      sign_in(user)
    end

    it_behaves_like 'hides the settings search bar' do
      subject do
        get(:show, params: { namespace_id: project.namespace.to_param, project_id: project, id: protected_tag.id })
      end
    end
  end

  describe "DELETE #destroy" do
    let(:project) { create(:project) }
    let(:protected_tag) { create(:protected_tag, :developers_can_create, project: project) }
    let(:user) { create(:user) }

    before do
      project.add_maintainer(user)
      sign_in(user)
    end

    it "deletes the protected tag" do
      delete(:destroy, params: { namespace_id: project.namespace.to_param, project_id: project, id: protected_tag.id })

      expect { ProtectedTag.find(protected_tag.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
