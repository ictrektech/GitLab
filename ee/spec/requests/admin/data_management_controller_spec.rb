# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::DataManagementController, :enable_admin_mode, feature_category: :geo_replication do
  include AdminModeHelper
  include EE::GeoHelpers

  let_it_be(:admin) { create(:admin) }

  let(:path) { admin_data_management_path }
  let(:show_path) { "#{path}/#{model_name}/#{id}" }
  let(:index_path) { "#{path}/#{model_name}" }

  before do
    sign_in(admin)
  end

  shared_context 'with data management available' do
    before do
      stub_licensed_features(data_management: true)
      allow(::Gitlab::Geo).to receive(:enabled?).and_return(true)
    end
  end

  describe 'before_actions' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:model) { create(:project) }
    let_it_be(:model_name) { Gitlab::Geo::ModelMapper.convert_to_name(model.class).pluralize }
    let_it_be(:id) { model.id }

    where(:geo_enabled, :data_management_enabled, :expected_status) do
      true  | true  | :ok
      true  | false | :not_found
      false | true  | :not_found
      false | false | :not_found
    end

    with_them do
      before do
        stub_licensed_features(data_management: data_management_enabled)
        allow(::Gitlab::Geo).to receive(:enabled?).and_return(geo_enabled)
      end

      it '#index renders with expected status' do
        get index_path

        expect(response).to have_gitlab_http_status(expected_status)
        expect(response).to render_template(:index) if expected_status == :ok
      end

      it '#show renders with expected status' do
        get show_path

        expect(response).to have_gitlab_http_status(expected_status)
        expect(response).to render_template(:show) if expected_status == :ok
      end
    end
  end

  context 'when model is valid' do
    include_context 'with data management available'

    let_it_be(:default_model) { Project }

    before do
      # Some replicators are disabled by config in the test environment (e.g. registry)
      ::Gitlab::Geo::REPLICATOR_CLASSES.each do |replicator_class|
        allow(replicator_class).to receive(:replication_enabled?).and_return(true)
      end
    end

    where(model_classes: Gitlab::Geo::ModelMapper.available_models)
    with_them do
      let(:model_name) { Gitlab::Geo::ModelMapper.convert_to_name(model_classes).pluralize }
      let(:model) { create(factory_name(model_classes)) } # rubocop:disable Rails/SaveBang -- this is creating a factory, not a record
      let(:id) { model.id }

      describe '#index' do
        it 'assigns @model_class with the correct class' do
          get index_path

          expect(assigns(:model_class)).to eq(model_classes)
          expect(response).to render_template(:index)
        end

        it 'uses the default model when no model_name parameter' do
          get path

          expect(assigns(:model_class)).to eq(default_model)
        end
      end

      describe '#show' do
        it 'assigns @model with the record found from ID' do
          get show_path

          expect(assigns(:model)).to eq(model)
          expect(response).to render_template(:show)
        end
      end
    end
  end

  context 'when the model replicator is disabled' do
    include_context 'with data management available'

    let_it_be(:model) { create(:lfs_object) }
    let(:model_name) { 'lfs_objects' }
    let(:id) { model.id }

    before do
      stub_feature_flags(Geo::LfsObjectReplicator.replication_enabled_feature_key => false)
    end

    it 'index redirects with a notice' do
      get index_path

      expect(response).to redirect_to(admin_data_management_path)
      expect(flash[:notice]).to eq(
        format(s_('Geo|Replication of %{replicable_title} is disabled on this site.'),
          replicable_title: Geo::LfsObjectReplicator.replicable_title_plural)
      )
    end

    it 'show still renders' do
      get show_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(response).to render_template(:show)
    end

    context 'when the data_management feature is not licensed' do
      before do
        stub_licensed_features(data_management: false)
      end

      it 'index renders 404 instead of redirecting' do
        get index_path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  context 'when no replicator is enabled' do
    include_context 'with data management available'

    before do
      ::Gitlab::Geo::REPLICATOR_CLASSES.each do |replicator_class|
        allow(replicator_class).to receive(:replication_enabled?).and_return(false)
      end
    end

    it 'index renders 404 when no model name is given' do
      get path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the Project replicator is disabled and no model name is given' do
    include_context 'with data management available'

    before do
      stub_feature_flags(Geo::ProjectRepositoryReplicator.replication_enabled_feature_key => false)
    end

    it 'index falls back to another replicable model' do
      get path

      expect(response).to render_template(:index)
      expect(assigns(:model_class)).not_to eq(Project)
      expect(Gitlab::Geo::ModelMapper.available_replicable_models).to include(assigns(:model_class))
    end
  end

  context 'when the model name is a replicable group' do
    include_context 'with data management available'

    let(:index_path) { "#{path}/uploads" }
    let(:legacy_uploads_enabled) { false }

    before do
      stub_feature_flags(geo_upload_replication: legacy_uploads_enabled)
    end

    context 'when the legacy replicator is disabled' do
      it 'renders the overview linking to the enabled partitions' do
        get index_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template(:replicable_group)
        expect(response.body).to include(list_admin_data_management_path(model_name: 'geo_project_uploads'))
        expect(response.body).to include(s_('Geo|Review stored data and data health within your instance.'))
      end

      it 'omits partitions whose replication is disabled' do
        stub_feature_flags(Geo::ProjectUploadReplicator.replication_enabled_feature_key => false)

        get index_path

        expect(response.body).not_to include(list_admin_data_management_path(model_name: 'geo_project_uploads'))
        expect(response.body).to include(list_admin_data_management_path(model_name: 'geo_user_uploads'))
      end

      it 'redirects with a notice when every partition is disabled' do
        partition_flags = ::Gitlab::Geo::REPLICATOR_CLASSES
          .select { |replicator| replicator.replicable_group == 'uploads' }
          .to_h { |replicator| [replicator.replication_enabled_feature_key, false] }
        stub_feature_flags(partition_flags)

        get index_path

        expect(response).to redirect_to(admin_data_management_path)
        expect(flash[:notice]).to eq(
          format(s_('Geo|Replication of %{replicable_title} is disabled on this site.'),
            replicable_title: Geo::UploadReplicator.replicable_title_plural)
        )
      end

      it 'renders the overview when the legacy model can no longer be resolved' do
        allow(::Gitlab::Geo::ModelMapper).to receive(:find_from_name).and_call_original
        allow(::Gitlab::Geo::ModelMapper).to receive(:find_from_name).with('upload').and_return(nil)

        get index_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template(:replicable_group)
      end

      it 'returns 404 without the data_management license' do
        stub_licensed_features(data_management: false)

        get index_path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the legacy replicator is enabled' do
      let(:legacy_uploads_enabled) { true }

      it 'renders the legacy list page' do
        get index_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template(:index)
      end
    end

    context 'when the model name is a partition' do
      let(:index_path) { "#{path}/geo_project_uploads" }

      it 'renders the list page' do
        get index_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template(:index)
      end
    end
  end

  context 'when model is not found' do
    let(:model_name) { 'projects' }
    let(:id) { 999 }

    it 'show renders 404' do
      get show_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when model is invalid' do
    let(:model_name) { 'invalids' }
    let(:id) { 1 }

    it 'index renders 404' do
      get index_path

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'show renders 404' do
      get show_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when model is singular' do
    let(:model_name) { 'upload' }
    let(:id) { 1 }

    it 'index renders 404' do
      get index_path

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'show renders 404' do
      get show_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
