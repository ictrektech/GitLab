# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::Geo::ReplicablesController, :geo, feature_category: :geo_replication do
  include AdminModeHelper
  include EE::GeoHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:primary_node) { create(:geo_node) }
  let_it_be(:secondary_node) { create(:geo_node, :secondary) }

  # With only the legacy flag off, "uploads" renders the partitions overview, covered by its own examples below
  let(:replicable_class) { Gitlab::Geo.replication_enabled_replicator_classes.excluding(Geo::UploadReplicator).sample }

  before do
    enable_admin_mode!(admin)
    login_as(admin)
  end

  subject do
    get url
    response
  end

  shared_examples 'license required' do
    context 'without a valid license' do
      it { is_expected.to have_gitlab_http_status(:forbidden) }
    end
  end

  describe 'GET /admin/geo/replicables/:replicable_name_plural' do
    let(:url) { "/admin/geo/replication/#{replicable_class.replicable_name_plural}" }

    it_behaves_like 'license required'

    context 'with a valid license' do
      before do
        stub_licensed_features(geo: true)

        get url
      end

      context 'when Geo is not enabled' do
        it { is_expected.to redirect_to(admin_geo_nodes_path) }
      end

      context 'when on a Geo primary' do
        before do
          stub_primary_node
        end

        it { is_expected.to redirect_to(admin_geo_nodes_path) }
      end

      context 'when on a Geo secondary' do
        before do
          stub_current_geo_node(secondary_node)
        end

        it 'redirects to the replicables page of the current site' do
          is_expected.to redirect_to(
            site_replicables_admin_geo_node_path(id: secondary_node.id, replicable_name_plural: replicable_class.replicable_name_plural)
          )
        end

        context 'when replication is disabled for the replicable' do
          before do
            stub_feature_flags(replicable_class.replication_enabled_feature_key => false)
          end

          it 'goes straight to the sites page instead of the site route' do
            is_expected.to redirect_to(admin_geo_nodes_path)
            expect(flash[:notice]).to eq("Replication of #{replicable_class.replicable_title_plural} is disabled on this site.")
          end
        end
      end
    end
  end

  describe 'GET /admin/geo/sites/:id/replicables/:replicable_name_plural' do
    let(:url) { "/admin/geo/sites/#{secondary_node.id}/replication/#{replicable_class.replicable_name_plural}" }

    it_behaves_like 'license required'

    context 'with a valid license' do
      before do
        stub_licensed_features(geo: true)
      end

      context 'when replication is disabled for the replicable' do
        before do
          stub_feature_flags(replicable_class.replication_enabled_feature_key => false)
        end

        it { is_expected.to redirect_to(admin_geo_nodes_path) }

        it 'explains why in a notice' do
          get url

          expect(flash[:notice]).to eq("Replication of #{replicable_class.replicable_title_plural} is disabled on this site.")
        end
      end

      context 'when the replicable name is unknown' do
        let(:url) { "/admin/geo/sites/#{secondary_node.id}/replication/invalid_names" }

        it { is_expected.to have_gitlab_http_status(:not_found) }
      end

      where(:current_node) { [nil, lazy { primary_node }, lazy { secondary_node }] }

      with_them do
        context 'loads node data' do
          before do
            stub_current_geo_node(current_node) if current_node.present?
          end

          it { is_expected.not_to be_redirect }

          it 'includes expected current and target ids' do
            get url

            expect(response.body).to include("geo-target-site-id=\"#{secondary_node.id}\"")
            if current_node.present?
              expect(response.body).to include("geo-current-site-id=\"#{current_node&.id}\"")
            else
              expect(response.body).not_to include("geo-current-site-id")
            end
          end
        end
      end
    end
  end

  describe 'GET /admin/geo/sites/:id/replication/uploads' do
    let(:url) { "/admin/geo/sites/#{secondary_node.id}/replication/uploads" }
    let(:project_upload_path) { "/admin/geo/sites/#{secondary_node.id}/replication/project_uploads" }

    before do
      stub_licensed_features(geo: true)
    end

    context 'when the legacy upload replicator is disabled' do
      before do
        stub_feature_flags(geo_upload_replication: false)
      end

      it 'renders the overview of the enabled upload partitions' do
        get url

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template :replicable_group
        expect(response.body).to include(format(s_('Geo|Geo replication - %{site_name}'), site_name: secondary_node.name))
        expect(response.body).to include(s_('Geo|Uploads are replicated by type. Select a type to review its replication status.'))
        expect(response.body).to include(project_upload_path)
      end

      it 'does not link to a disabled upload partition' do
        stub_feature_flags(Geo::ProjectUploadReplicator.replication_enabled_feature_key => false)

        get url

        expect(response).to render_template :replicable_group
        expect(response.body).not_to include(project_upload_path)
        expect(response.body).to include("/admin/geo/sites/#{secondary_node.id}/replication/user_uploads")
      end

      it 'still renders the overview when the legacy replicator cannot be resolved' do
        allow(Gitlab::Geo::Replicator).to receive(:for_replicable_name).and_call_original
        allow(Gitlab::Geo::Replicator).to receive(:for_replicable_name).with('upload').and_raise(NotImplementedError)

        get url

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template :replicable_group
      end

      context 'when every upload replicator is disabled' do
        before do
          Gitlab::Geo::REPLICATOR_CLASSES.each do |klass|
            stub_feature_flags(klass.replication_enabled_feature_key => false) if klass.model <= ::Upload
          end
        end

        it 'keeps the disabled redirect and its notice' do
          get url

          expect(response).to redirect_to(admin_geo_nodes_path)
          expect(flash[:notice]).to eq(
            format(s_('Geo|Replication of %{replicable_title} is disabled on this site.'),
              replicable_title: Geo::UploadReplicator.replicable_title_plural))
        end
      end
    end

    context 'when the legacy upload replicator is enabled' do
      before do
        stub_feature_flags(geo_upload_replication: true)
      end

      it 'renders the legacy page' do
        get url

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template :index
      end
    end

    it 'renders the partition page for a partition slug' do
      get project_upload_path

      expect(response).to render_template :index
    end
  end

  describe 'GET /admin/geo/replication/uploads' do
    let(:url) { '/admin/geo/replication/uploads' }

    before do
      stub_licensed_features(geo: true)
      stub_feature_flags(geo_upload_replication: false)
    end

    it 'redirects to the sites page on a primary' do
      stub_primary_node

      get url

      expect(response).to redirect_to(admin_geo_nodes_path)
      expect(flash[:notice]).to be_nil
    end

    it 'redirects to the current site route on a secondary' do
      stub_current_geo_node(secondary_node)

      get url

      expect(response).to redirect_to(
        site_replicables_admin_geo_node_path(id: secondary_node.id, replicable_name_plural: 'uploads')
      )
    end
  end

  describe 'GET /admin/geo/sites/:id/replicables/:replicable_name_plural/:replicable_id' do
    let(:base_url) { "/admin/geo/sites/#{secondary_node.id}/replication" }
    let(:url) do
      replicable_name = replicable_class.replicable_name_plural
      # rubocop:disable Rails/SaveBang -- This is not creating a record but a factory.
      # See Rubocop issue: https://github.com/thoughtbot/factory_bot/issues/1620
      model_record = create(factory_name(replicable_class.model))
      # rubocop:enable Rails/SaveBang

      "#{base_url}/#{replicable_name}/#{model_record.id}"
    end

    it_behaves_like 'license required'

    context 'with a valid license' do
      before do
        stub_licensed_features(geo: true)
      end

      where(:current_node) { [nil, lazy { primary_node }, lazy { secondary_node }] }

      with_them do
        context 'valid replicable params' do
          it 'renders show template' do
            get url

            expect(response).to render_template :show
          end
        end

        context 'invalid replicable id' do
          it 'renders 404' do
            get "#{base_url}/#{replicable_class.replicable_name_plural}/invalid_id"

            expect(response).to have_gitlab_http_status(:not_found)
          end
        end

        context 'invalid replicable_name' do
          it 'renders 404' do
            get "#{base_url}/invalid_names/1"

            expect(response).to have_gitlab_http_status(:not_found)
          end
        end
      end
    end
  end
end
