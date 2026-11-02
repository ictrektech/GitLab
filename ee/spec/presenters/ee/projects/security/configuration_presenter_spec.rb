# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::ConfigurationPresenter, feature_category: :software_composition_analysis do
  using RSpec::Parameterized::TableSyntax
  include Gitlab::Routing.url_helpers
  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :repository, maintainers: current_user) }

  let(:presenter) { described_class.new(project, current_user: current_user) }

  describe '#to_h' do
    subject(:result) { presenter.to_h }

    it 'includes the vulnerability archive export path' do
      expect(result[:vulnerability_archive_export_path]).to eq(
        "/api/v4/security/projects/#{project.id}/vulnerability_archive_exports"
      )
    end

    it 'reports security_training_enabled' do
      allow(project).to receive(:security_training_available?).and_return(true)

      expect(result[:security_training_enabled]).to be_truthy
    end

    it 'includes a default value for container_scanning_for_registry_enabled' do
      expect(result[:container_scanning_for_registry_enabled]).to be(false)
    end

    it 'includes a default value for cvs_for_container_scanning_enabled' do
      expect(result[:cvs_for_container_scanning_enabled]).to be(true)
    end

    it 'includes a default value for cvs_for_dependency_scanning_enabled' do
      expect(result[:cvs_for_dependency_scanning_enabled]).to be(true)
    end

    it 'includes a default value for license_scanning_for_cyclonedx_enabled' do
      expect(result[:license_scanning_for_cyclonedx_enabled]).to be(true)
    end

    it 'includes a default value for secret_push_protection_enabled' do
      expect(result[:secret_push_protection_enabled]).to be(false)
    end

    it 'includes a default value for validity_checks_enabled' do
      expect(result[:validity_checks_enabled]).to be(false)
    end

    it 'includes validity_checks_available' do
      expect(result).to have_key(:validity_checks_available)
    end

    it 'includes license_configuration_source' do
      expect(result[:license_configuration_source]).to eq('SBOM')
    end

    context 'when security setting is nil' do
      before do
        allow(project).to receive(:security_setting).and_return(nil)
      end

      it 'returns the default value' do
        expect(result[:license_configuration_source]).to eq('SBOM')
      end
    end

    describe 'secret_push_protection_available' do
      context 'when instance setting is enabled' do
        before do
          allow(Gitlab::CurrentSettings.current_application_settings)
            .to receive(:secret_push_protection_available).and_return(true)
        end

        it 'returns true' do
          expect(result[:secret_push_protection_available]).to be(true)
        end
      end

      context 'when instance setting is disabled' do
        before do
          allow(Gitlab::CurrentSettings.current_application_settings)
            .to receive(:secret_push_protection_available).and_return(false)
        end

        it 'returns false' do
          expect(result[:secret_push_protection_available]).to be(false)
        end
      end
    end

    describe 'upgrade_path' do
      it 'includes the promo pricing url by default' do
        expect(result[:upgrade_path]).to eq(promo_pricing_url)
      end

      context 'on GitLab.com without security_dashboard license', :saas do
        let_it_be(:root_namespace) { create(:group, owners: current_user) }
        let_it_be(:project) { create(:project, namespace: root_namespace) }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it 'returns the project security discover path' do
          expect(result[:upgrade_path]).to eq(project_security_discover_path(project))
        end
      end
    end

    describe 'group_manage_attributes_path' do
      context 'when project has root group' do
        let(:parent) { build_stubbed(:group) }
        let(:project) { build_stubbed(:project, namespace: parent) }

        it 'returns the group security configuration path deep-linked to the attributes tab' do
          expect(result[:group_manage_attributes_path]).to eq(
            group_security_configuration_path(parent, tab: 'attributes')
          )
        end
      end

      context 'when project is under a user namespace' do
        let(:parent) { build_stubbed(:user_namespace) }
        let(:project) { build_stubbed(:project, namespace: parent) }

        it 'returns nil' do
          expect(result[:group_manage_attributes_path]).to be_nil
        end
      end
    end

    describe 'max_tracked_refs' do
      it 'returns the default limit' do
        stub_feature_flags(vac_increased_limit: false)

        expect(result[:max_tracked_refs]).to eq(Security::ProjectTrackedContext::MAX_TRACKED_REFS_PER_PROJECT)
      end

      context 'when vac_increased_limit feature flag is enabled' do
        before do
          stub_feature_flags(vac_increased_limit: project)
        end

        it 'returns the increased limit' do
          expect(result[:max_tracked_refs]).to eq(Security::ProjectTrackedContext::MAX_TRACKED_REFS_INCREASED)
        end
      end
    end
  end

  describe '#to_html_data_attribute' do
    subject(:html_data) { presenter.to_html_data_attribute }

    describe 'business_logic configured status' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, :repository, group: group) }

      let(:configured) do
        Gitlab::Json.parse(html_data[:features]).find { |scan| scan['type'] == 'business_logic' }['configured']
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it 'is false without a Business Logic scan profile' do
        create(:security_scan_profile, namespace: group, scan_type: :sast, projects: [project])

        expect(configured).to be(false)
      end

      it 'is true when a Business Logic scan profile is attached' do
        create(:security_scan_profile, namespace: group, scan_type: :business_logic, projects: [project])

        expect(configured).to be(true)
      end
    end

    describe 'skillguard configured status' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, :repository, group: group) }

      let(:configured) do
        Gitlab::Json.parse(html_data[:features]).find { |scan| scan['type'] == 'skillguard' }['configured']
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'is false without a SkillGuard scan profile' do
        create(:security_scan_profile, namespace: group, scan_type: :sast, projects: [project])

        expect(configured).to be(false)
      end

      it 'is true when a SkillGuard scan profile is attached' do
        create(:security_scan_profile, namespace: group, scan_type: :skillguard, projects: [project])

        expect(configured).to be(true)
      end
    end

    context 'with container_scanning_for_registry licensed' do
      before do
        stub_licensed_features(container_scanning_for_registry: true)
      end

      it 'includes container_scanning_for_registry feature information' do
        feature = Gitlab::Json.parse(html_data[:features]).find do |scan|
          scan['type'] == 'container_scanning_for_registry'
        end

        expect(feature['type']).to eq('container_scanning_for_registry')
        expect(feature['configured']).to be(false)
        expect(feature['configuration_path']).to be_nil
        expect(feature['available']).to be(true)
        expect(feature['can_enable_by_merge_request']).to be(false)
        expect(feature['meta_info_path']).to be_nil
        expect(feature['security_features']).not_to be_empty
      end
    end

    where(:container_licensed, :dependency_licensed, :include_cs, :include_ds) do
      true  | true  | true  | true
      false | true  | false | true
      true  | false | true  | false
    end

    with_them do
      before do
        stub_licensed_features(container_scanning: container_licensed, dependency_scanning: dependency_licensed)
      end

      it 'includes or excludes CVS features based on availability' do
        types = Gitlab::Json.parse(html_data[:features]).pluck('type')

        if include_cs
          expect(types).to include('cvs_for_container_scanning')
        else
          expect(types).not_to include('cvs_for_container_scanning')
        end

        if include_ds
          expect(types).to include('cvs_for_dependency_scanning')
        else
          expect(types).not_to include('cvs_for_dependency_scanning')
        end
      end
    end

    context 'when license_scanning license is enabled' do
      before do
        stub_licensed_features(license_scanning: true)
      end

      it 'includes license_scanning_for_cyclonedx feature information' do
        feature = Gitlab::Json.parse(html_data[:features]).find do |scan|
          scan['type'] == 'license_scanning_for_cyclonedx'
        end

        expect(feature['type']).to eq('license_scanning_for_cyclonedx')
        expect(feature['configured']).to be(true)
        expect(feature['configuration_path']).to be_nil
        expect(feature['available']).to be(false)
        expect(feature['can_enable_by_merge_request']).to be(false)
        expect(feature['meta_info_path']).to be_nil
        expect(feature['security_features']).not_to be_empty
      end
    end

    describe 'license_scanning_for_cyclonedx availability' do
      where(:licensed, :included) do
        true  | true
        false | false
      end

      with_them do
        before do
          stub_licensed_features(license_scanning: licensed)
        end

        it 'includes or excludes license_scanning_for_cyclonedx based on availability' do
          types = Gitlab::Json.parse(html_data[:features]).pluck('type')

          if included
            expect(types).to include('license_scanning_for_cyclonedx')
          else
            expect(types).not_to include('license_scanning_for_cyclonedx')
          end
        end
      end
    end

    context 'with attributes permissions' do
      context 'with a project-scoped custom role granting only read_security_attribute' do
        let_it_be(:parent) { create(:group) }
        let_it_be(:project) { create(:project, namespace: parent) }
        let_it_be(:current_user) { create(:user) }
        let_it_be(:role) { create(:member_role, :reporter, :read_security_attribute, namespace: parent) }

        let_it_be(:membership) do
          create(:project_member, :reporter, member_role: role, user: current_user, source: project)
        end

        before do
          stub_licensed_features(security_attributes: true, custom_roles: true)
        end

        it 'reflects the project-scoped grant' do
          expect(html_data[:can_read_attributes]).to be true
          expect(html_data[:can_manage_attributes]).to be false
        end
      end
    end
  end
end
