# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::AccessController, feature_category: :organization do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }

  describe 'GET #index' do
    subject(:gitlab_request) { get access_organization_path(organization) }

    context 'when the user is not signed in' do
      it_behaves_like 'organization - redirects to sign in page'
    end

    context 'when the user is signed in' do
      before do
        sign_in(user)
      end

      context 'when the user is an organization owner' do
        before_all do
          create(:organization_user, :owner, organization: organization, user: user)
        end

        it 'renders the mount element', :aggregate_failures do
          gitlab_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('id="js-organization-access"')
          expect(response.body).to include(%(data-organization-path="#{organization.path}"))
        end

        context 'when the `organization_access_ui` feature flag is disabled' do
          before do
            stub_feature_flags(organization_access_ui: false)
          end

          it_behaves_like 'organization - not found response'
        end

        it_behaves_like 'organization - action disabled by org_pages release flag'
      end

      context 'when the user is an organization member without the owner role' do
        let_it_be(:member) { create(:user) }

        before_all do
          create(:organization_user, organization: organization, user: member)
        end

        before do
          sign_in(member)
        end

        it_behaves_like 'organization - not found response'
      end

      context 'when the user is not an organization member' do
        it_behaves_like 'organization - not found response'
      end
    end
  end

  describe 'GET #artifact_registry' do
    subject(:gitlab_request) { get artifact_registry_access_organization_path(organization) }

    context 'when the user is not signed in' do
      it_behaves_like 'organization - redirects to sign in page'
    end

    context 'when the user is signed in as an organization owner' do
      before_all do
        create(:organization_user, :owner, organization: organization, user: user)
      end

      before do
        sign_in(user)
      end

      it 'renders the mount element', :aggregate_failures do
        gitlab_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('id="js-organization-access-artifact-registry"')
        expect(response.body).to include(%(data-organization-path="#{organization.path}"))
      end

      it 'ends the breadcrumbs with Organization access, then Artifact Registry' do
        gitlab_request

        breadcrumbs_json = Nokogiri::HTML(response.body)
          .at_css('#js-vue-page-breadcrumbs')['data-breadcrumbs-json']
        breadcrumbs = Gitlab::Json::SafeParser.parse(breadcrumbs_json).last(2)

        expect(breadcrumbs).to match([
          a_hash_including(
            'text' => s_('Organization|Organization access'),
            'href' => access_organization_path(organization)
          ),
          a_hash_including('text' => s_('ArtifactRegistry|Artifact Registry'))
        ])
      end

      context 'when the `organization_access_ui` feature flag is disabled' do
        before do
          stub_feature_flags(organization_access_ui: false)
        end

        it_behaves_like 'organization - not found response'
      end
    end
  end
end
