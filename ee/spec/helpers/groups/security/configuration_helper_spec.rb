# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Security::ConfigurationHelper, feature_category: :security_testing_configuration do
  let_it_be_with_refind(:group) { create(:group) }
  let_it_be_with_refind(:user) { create(:user) }

  before do
    allow(helper).to receive_messages(current_user: user, can?: false)
  end

  describe '#group_security_configuration_data' do
    let(:group) { build_stubbed(:group) }

    subject(:group_security_configuration_data) do
      helper.group_security_configuration_data(group)
    end

    before do
      allow(helper).to receive(:scan_coverage_banner_payload).and_return(nil)
    end

    it 'builds correct hash' do
      expect(group_security_configuration_data).to eq({
        namespace_id: group.root_ancestor.id,
        group_id: group.id,
        group_full_path: group.full_path,
        group_name: group.name,
        root_group_name: group.name,
        security_inventory_path: group_security_inventory_path(group),
        can_read_attributes: 'false',
        can_manage_attributes: 'false',
        can_read_scan_profiles: 'false',
        can_apply_profiles: 'false',
        scan_coverage_banner: 'null'
      })
    end

    context 'with a nested subgroup' do
      let(:subgroup) { build_stubbed(:group, parent: group) }
      let(:nested_subgroup) { build_stubbed(:group, parent: subgroup) }

      it 'names the root ancestor rather than a closer parent' do
        expect(helper.group_security_configuration_data(nested_subgroup)).to include(
          group_name: nested_subgroup.name,
          root_group_name: group.name
        )
      end
    end

    context 'when a scan coverage banner payload is present' do
      let(:payload) { { variant: 'tip', title: 'Title', message: 'Message', cta_text: 'CTA', cta_url: '/path' } }

      before do
        allow(helper).to receive(:scan_coverage_banner_payload).and_return(payload)
      end

      it 'serializes the payload as camelCase JSON' do
        json = Gitlab::Json::SafeParser.parse(group_security_configuration_data[:scan_coverage_banner])

        expect(json).to eq({
          'variant' => 'tip', 'title' => 'Title', 'message' => 'Message', 'ctaText' => 'CTA', 'ctaUrl' => '/path'
        })
      end
    end

    context 'when the scan coverage banner payload is nil' do
      it 'serializes to the JSON literal null', :aggregate_failures do
        expect(group_security_configuration_data[:scan_coverage_banner]).to eq('null')
        expect(Gitlab::Json::SafeParser.parse(group_security_configuration_data[:scan_coverage_banner])).to be_nil
      end
    end
  end

  describe '#scan_coverage_banner_payload' do
    let_it_be(:maintainer) { create(:user, maintainer_of: group) }
    let_it_be(:developer) { create(:user, developer_of: group) }

    let(:payload) { { variant: 'tip', message: 'test', cta_text: 'Set up scanning', cta_url: '/test' } }

    before do
      allow_next_instance_of(Security::ScanCoverageBanners::GenerateContentService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: payload))
      end
    end

    context 'when the user is a Maintainer and the group is licensed' do
      before do
        allow(helper).to receive(:current_user).and_return(maintainer)
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'returns the generated payload' do
        expect(helper.scan_coverage_banner_payload(group)).to eq(payload)
      end
    end

    context 'when the user is only a Developer' do
      before do
        allow(helper).to receive(:current_user).and_return(developer)
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'returns nil' do
        expect(helper.scan_coverage_banner_payload(group)).to be_nil
      end
    end

    context 'when the user is a Security Manager (custom role) on the group' do
      let_it_be(:security_manager) { create(:user, security_manager_of: group) }

      before do
        allow(helper).to receive(:current_user).and_return(security_manager)
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'returns the generated payload' do
        expect(helper.scan_coverage_banner_payload(group)).to eq(payload)
      end
    end

    context 'when the security_profile_banner feature flag is disabled' do
      before do
        stub_feature_flags(security_profile_banner: false)
        allow(helper).to receive(:current_user).and_return(maintainer)
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'returns nil without calling the generate service', :aggregate_failures do
        expect(Security::ScanCoverageBanners::GenerateContentService).not_to receive(:new)
        expect(helper.scan_coverage_banner_payload(group)).to be_nil
      end
    end

    context 'when the group is not licensed' do
      before do
        allow(helper).to receive(:current_user).and_return(maintainer)
        stub_licensed_features(security_scan_profiles: false)
      end

      it 'returns nil without calling the generate service', :aggregate_failures do
        expect(Security::ScanCoverageBanners::GenerateContentService).not_to receive(:new)
        expect(helper.scan_coverage_banner_payload(group)).to be_nil
      end
    end

    context 'when the generate service fails' do
      before do
        allow(helper).to receive(:current_user).and_return(maintainer)
        stub_licensed_features(security_scan_profiles: true)
        allow_next_instance_of(Security::ScanCoverageBanners::GenerateContentService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Group has no projects'))
        end
      end

      it 'returns nil' do
        expect(helper.scan_coverage_banner_payload(group)).to be_nil
      end
    end

    context 'when the Maintainer dismissed the banner' do
      let_it_be_with_refind(:dismissing_maintainer) { create(:user, maintainer_of: group) }

      before do
        allow(helper).to receive(:current_user).and_return(dismissing_maintainer)
        stub_licensed_features(security_scan_profiles: true)
      end

      context 'when within the snooze period' do
        before_all do
          create(:group_callout,
            user: dismissing_maintainer,
            group: group,
            feature_name: :scan_coverage_recommendation_banner,
            dismissed_at: 34.days.ago)
        end

        it 'returns nil without calling the generate service', :aggregate_failures do
          expect(Security::ScanCoverageBanners::GenerateContentService).not_to receive(:new)
          expect(helper.scan_coverage_banner_payload(group)).to be_nil
        end
      end

      context 'when outside the snooze period' do
        before_all do
          create(:group_callout,
            user: dismissing_maintainer,
            group: group,
            feature_name: :scan_coverage_recommendation_banner,
            dismissed_at: 36.days.ago)
        end

        it 'returns the generated payload' do
          expect(helper.scan_coverage_banner_payload(group)).to eq(payload)
        end
      end
    end

    context 'when the group passed in is a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_maintainer) { create(:user, maintainer_of: subgroup) }

      before do
        allow(helper).to receive(:current_user).and_return(subgroup_maintainer)
        stub_licensed_features(security_scan_profiles: true)
      end

      it 'evaluates the ability and builds the payload against the subgroup, not its root ancestor',
        :aggregate_failures do
        expect_next_instance_of(Security::ScanCoverageBanners::GenerateContentService, subgroup) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: payload))
        end

        expect(helper.scan_coverage_banner_payload(subgroup)).to eq(payload)
      end
    end
  end
end
