# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::Availability, feature_category: :dependency_firewall do
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be_with_reload(:project) { create(:project, group: subgroup) }

  describe '.feature_flag_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_phase1: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.feature_flag_enabled?(root_group)).to be(false)
        expect(described_class.feature_flag_enabled?(subgroup)).to be(false)
        expect(described_class.feature_flag_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_phase1: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.feature_flag_enabled?(root_group)).to be(true)
        expect(described_class.feature_flag_enabled?(subgroup)).to be(true)
        expect(described_class.feature_flag_enabled?(project)).to be(true)
      end
    end

    context 'when the flag is enabled for a subgroup instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_phase1: subgroup)
      end

      it 'is false, so only one enablement on the top-level group is needed', :aggregate_failures do
        expect(described_class.feature_flag_enabled?(subgroup)).to be(false)
        expect(described_class.feature_flag_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the project instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_phase1: project)
      end

      it 'is false, so only one enablement on the top-level group is needed' do
        expect(described_class.feature_flag_enabled?(project)).to be(false)
      end
    end

    context 'with a nil container' do
      it 'falls back to the global gate', :aggregate_failures do
        expect(described_class.feature_flag_enabled?(nil)).to be(true)

        stub_feature_flags(dependency_firewall_phase1: false)

        expect(described_class.feature_flag_enabled?(nil)).to be(false)
      end
    end
  end

  describe '.available?' do
    before do
      stub_feature_flags(dependency_firewall_phase1: root_group)
    end

    it 'is true when the flag and the license are both present' do
      stub_licensed_features(dependency_firewall: true)

      expect(described_class.available?(project)).to be(true)
    end

    it 'is false without the license' do
      stub_licensed_features(dependency_firewall: false)

      expect(described_class.available?(project)).to be(false)
    end

    it 'is false without the flag' do
      stub_feature_flags(dependency_firewall_phase1: false)
      stub_licensed_features(dependency_firewall: true)

      expect(described_class.available?(project)).to be(false)
    end

    it 'is false for a nil container, whatever the global flag state' do
      stub_licensed_features(dependency_firewall: true)

      expect(described_class.available?(nil)).to be(false)
    end
  end

  describe '.phase2_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_phase2: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.phase2_enabled?(root_group)).to be(false)
        expect(described_class.phase2_enabled?(subgroup)).to be(false)
        expect(described_class.phase2_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_phase2: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.phase2_enabled?(root_group)).to be(true)
        expect(described_class.phase2_enabled?(subgroup)).to be(true)
        expect(described_class.phase2_enabled?(project)).to be(true)
      end
    end

    context 'when the flag is enabled for a subgroup instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_phase2: subgroup)
      end

      it 'is false, so only one enablement on the top-level group is needed', :aggregate_failures do
        expect(described_class.phase2_enabled?(subgroup)).to be(false)
        expect(described_class.phase2_enabled?(project)).to be(false)
      end
    end
  end

  describe '.dashboard_v2_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_dashboard_v2: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.dashboard_v2_enabled?(root_group)).to be(false)
        expect(described_class.dashboard_v2_enabled?(subgroup)).to be(false)
        expect(described_class.dashboard_v2_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_dashboard_v2: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.dashboard_v2_enabled?(root_group)).to be(true)
        expect(described_class.dashboard_v2_enabled?(subgroup)).to be(true)
        expect(described_class.dashboard_v2_enabled?(project)).to be(true)
      end
    end

    context 'with a nil container' do
      it 'falls back to the global gate', :aggregate_failures do
        stub_feature_flags(dependency_firewall_dashboard_v2: true)

        expect(described_class.dashboard_v2_enabled?(nil)).to be(true)

        stub_feature_flags(dependency_firewall_dashboard_v2: false)

        expect(described_class.dashboard_v2_enabled?(nil)).to be(false)
      end
    end
  end

  describe '.group_prevented_stats_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_group_prevented_stats: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.group_prevented_stats_enabled?(root_group)).to be(false)
        expect(described_class.group_prevented_stats_enabled?(subgroup)).to be(false)
        expect(described_class.group_prevented_stats_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_group_prevented_stats: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.group_prevented_stats_enabled?(root_group)).to be(true)
        expect(described_class.group_prevented_stats_enabled?(subgroup)).to be(true)
        expect(described_class.group_prevented_stats_enabled?(project)).to be(true)
      end
    end

    context 'with a nil container' do
      it 'falls back to the global gate', :aggregate_failures do
        stub_feature_flags(dependency_firewall_group_prevented_stats: true)

        expect(described_class.group_prevented_stats_enabled?(nil)).to be(true)

        stub_feature_flags(dependency_firewall_group_prevented_stats: false)

        expect(described_class.group_prevented_stats_enabled?(nil)).to be(false)
      end
    end
  end

  describe '.group_prevented_stats_enabled_for_root_id?' do
    let_it_be(:other_root) { create(:group) }

    before do
      stub_feature_flags(dependency_firewall_group_prevented_stats: root_group)
    end

    it 'checks the flag for the root group id without loading the group', :aggregate_failures do
      recorder = ActiveRecord::QueryRecorder.new do
        expect(described_class.group_prevented_stats_enabled_for_root_id?(root_group.id)).to be(true)
        expect(described_class.group_prevented_stats_enabled_for_root_id?(other_root.id)).to be(false)
      end

      expect(recorder.count).to eq(0)
    end
  end

  describe '.group_prevented_stats_possibly_enabled?' do
    it 'is true when the flag is enabled for some root group' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: root_group)

      expect(described_class.group_prevented_stats_possibly_enabled?).to be(true)
    end

    it 'is true when the flag is enabled for everyone' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: true)

      expect(described_class.group_prevented_stats_possibly_enabled?).to be(true)
    end

    it 'is false when the flag has never been set', :clean_gitlab_redis_feature_flag, stub_feature_flags: false do
      expect(described_class.group_prevented_stats_possibly_enabled?).to be(false)
    end
  end

  describe '.access_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_access: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.access_enabled?(root_group)).to be(false)
        expect(described_class.access_enabled?(subgroup)).to be(false)
        expect(described_class.access_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_access: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.access_enabled?(root_group)).to be(true)
        expect(described_class.access_enabled?(subgroup)).to be(true)
        expect(described_class.access_enabled?(project)).to be(true)
      end
    end

    context 'when the flag is enabled for a subgroup instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_access: subgroup)
      end

      it 'is false, so only one enablement on the top-level group is needed', :aggregate_failures do
        expect(described_class.access_enabled?(subgroup)).to be(false)
        expect(described_class.access_enabled?(project)).to be(false)
      end
    end

    context 'with a nil container' do
      it 'falls back to the global gate', :aggregate_failures do
        stub_feature_flags(dependency_firewall_access: true)

        expect(described_class.access_enabled?(nil)).to be(true)

        stub_feature_flags(dependency_firewall_access: false)

        expect(described_class.access_enabled?(nil)).to be(false)
      end
    end
  end

  describe '.age_rule_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_age_rule: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.age_rule_enabled?(root_group)).to be(false)
        expect(described_class.age_rule_enabled?(subgroup)).to be(false)
        expect(described_class.age_rule_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_age_rule: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.age_rule_enabled?(root_group)).to be(true)
        expect(described_class.age_rule_enabled?(subgroup)).to be(true)
        expect(described_class.age_rule_enabled?(project)).to be(true)
      end
    end

    context 'when the flag is enabled for a subgroup instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_age_rule: subgroup)
      end

      it 'is false, so only one enablement on the top-level group is needed', :aggregate_failures do
        expect(described_class.age_rule_enabled?(subgroup)).to be(false)
        expect(described_class.age_rule_enabled?(project)).to be(false)
      end
    end

    context 'with a nil container' do
      it 'falls back to the global gate', :aggregate_failures do
        stub_feature_flags(dependency_firewall_age_rule: true)

        expect(described_class.age_rule_enabled?(nil)).to be(true)

        stub_feature_flags(dependency_firewall_age_rule: false)

        expect(described_class.age_rule_enabled?(nil)).to be(false)
      end
    end
  end

  describe '.package_version_enabled?' do
    context 'when the flag is disabled' do
      before do
        stub_feature_flags(dependency_firewall_package_version: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.package_version_enabled?(root_group)).to be(false)
        expect(described_class.package_version_enabled?(subgroup)).to be(false)
        expect(described_class.package_version_enabled?(project)).to be(false)
      end
    end

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_package_version: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.package_version_enabled?(root_group)).to be(true)
        expect(described_class.package_version_enabled?(subgroup)).to be(true)
        expect(described_class.package_version_enabled?(project)).to be(true)
      end
    end

    context 'when the flag is enabled for a subgroup instead of the top-level group' do
      before do
        stub_feature_flags(dependency_firewall_package_version: subgroup)
      end

      it 'is false, so only one enablement on the top-level group is needed', :aggregate_failures do
        expect(described_class.package_version_enabled?(subgroup)).to be(false)
        expect(described_class.package_version_enabled?(project)).to be(false)
      end
    end

    context 'with a nil container' do
      context 'when the flag is enabled globally' do
        before do
          stub_feature_flags(dependency_firewall_package_version: true)
        end

        it 'is true' do
          expect(described_class.package_version_enabled?(nil)).to be(true)
        end
      end

      context 'when the flag is disabled globally' do
        before do
          stub_feature_flags(dependency_firewall_package_version: false)
        end

        it 'is false' do
          expect(described_class.package_version_enabled?(nil)).to be(false)
        end
      end
    end
  end

  describe '.package_version_rules_enabled?' do
    context 'when both flags are enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_access: root_group, dependency_firewall_package_version: root_group)
      end

      it 'covers the group, its subgroups and its projects', :aggregate_failures do
        expect(described_class.package_version_rules_enabled?(root_group)).to be(true)
        expect(described_class.package_version_rules_enabled?(subgroup)).to be(true)
        expect(described_class.package_version_rules_enabled?(project)).to be(true)
      end
    end

    context 'when only the access flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_access: root_group, dependency_firewall_package_version: false)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.package_version_rules_enabled?(root_group)).to be(false)
        expect(described_class.package_version_rules_enabled?(project)).to be(false)
      end
    end

    context 'when only the package_version flag is enabled for the root group' do
      before do
        stub_feature_flags(dependency_firewall_access: false, dependency_firewall_package_version: root_group)
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.package_version_rules_enabled?(root_group)).to be(false)
        expect(described_class.package_version_rules_enabled?(project)).to be(false)
      end
    end

    context 'when the flags are enabled for different groups' do
      before do
        stub_feature_flags(dependency_firewall_access: root_group, dependency_firewall_package_version: create(:group))
      end

      it 'is false for every container', :aggregate_failures do
        expect(described_class.package_version_rules_enabled?(root_group)).to be(false)
        expect(described_class.package_version_rules_enabled?(project)).to be(false)
      end
    end
  end

  describe '.group_dashboard_v2_enabled?' do
    it 'is true when both flags are enabled' do
      expect(described_class.group_dashboard_v2_enabled?(subgroup)).to be(true)
    end

    it 'is false when the dashboard flag is disabled' do
      stub_feature_flags(dependency_firewall_dashboard_v2: false)

      expect(described_class.group_dashboard_v2_enabled?(subgroup)).to be(false)
    end

    it 'is false when the group prevented stats flag is disabled' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: false)

      expect(described_class.group_dashboard_v2_enabled?(subgroup)).to be(false)
    end
  end

  describe '.namespace_configurable?' do
    before do
      stub_feature_flags(dependency_firewall_phase1: root_group)
      stub_licensed_features(dependency_firewall: true)
      stub_saas_features(dependency_firewall: true)
    end

    it 'is true for a root group' do
      expect(described_class.namespace_configurable?(root_group)).to be(true)
    end

    it 'is false for a subgroup' do
      expect(described_class.namespace_configurable?(subgroup)).to be(false)
    end

    it 'is false when the SaaS feature is unavailable' do
      stub_saas_features(dependency_firewall: false)

      expect(described_class.namespace_configurable?(root_group)).to be(false)
    end

    it 'is false without the license' do
      stub_licensed_features(dependency_firewall: false)

      expect(described_class.namespace_configurable?(root_group)).to be(false)
    end

    it 'is false without the flag' do
      stub_feature_flags(dependency_firewall_phase1: false)

      expect(described_class.namespace_configurable?(root_group)).to be(false)
    end

    it 'is false for a nil group' do
      expect(described_class.namespace_configurable?(nil)).to be(false)
    end

    # The toggle would be impossible to switch on if its own surface depended on it.
    it 'does not depend on the namespace setting' do
      root_group.namespace_settings.update!(dependency_firewall_enabled: false)

      expect(described_class.namespace_configurable?(root_group)).to be(true)
    end
  end

  describe '.instance_configurable?' do
    before do
      stub_licensed_features(dependency_firewall: true)
      stub_saas_features(dependency_firewall: false)
    end

    it 'is true with the license and the flag' do
      expect(described_class.instance_configurable?).to be(true)
    end

    it 'is false on .com, which enables per namespace instead' do
      stub_saas_features(dependency_firewall: true)

      expect(described_class.instance_configurable?).to be(false)
    end

    it 'is false without the license' do
      stub_licensed_features(dependency_firewall: false)

      expect(described_class.instance_configurable?).to be(false)
    end

    it 'is false without the flag' do
      stub_feature_flags(dependency_firewall_phase1: false)

      expect(described_class.instance_configurable?).to be(false)
    end
  end

  describe '.enforced_for?' do
    before do
      stub_feature_flags(dependency_firewall_phase1: root_group)
      stub_licensed_features(dependency_firewall: true)
    end

    context 'on .com, reading the namespace toggle' do
      before do
        stub_saas_features(dependency_firewall: true)
        root_group.namespace_settings.update!(dependency_firewall_enabled: true)
      end

      it 'is true with the flag, the license and the setting' do
        expect(described_class.enforced_for?(project)).to be(true)
      end

      it 'is false when the root group setting is off' do
        root_group.namespace_settings.update!(dependency_firewall_enabled: false)

        expect(described_class.enforced_for?(project)).to be(false)
      end

      it 'ignores the instance toggle' do
        root_group.namespace_settings.update!(dependency_firewall_enabled: false)
        stub_ee_application_setting(dependency_firewall_enabled: true)

        expect(described_class.enforced_for?(project)).to be(false)
      end

      it 'is false without the license' do
        stub_licensed_features(dependency_firewall: false)

        expect(described_class.enforced_for?(project)).to be(false)
      end

      it 'is false without the flag' do
        stub_feature_flags(dependency_firewall_phase1: false)

        expect(described_class.enforced_for?(project)).to be(false)
      end
    end

    context 'on self-managed, reading the instance toggle' do
      before do
        stub_saas_features(dependency_firewall: false)
        stub_ee_application_setting(dependency_firewall_enabled: true)
      end

      it 'is true with the flag, the license and the setting' do
        expect(described_class.enforced_for?(project)).to be(true)
      end

      it 'is false when the instance setting is off' do
        stub_ee_application_setting(dependency_firewall_enabled: false)

        expect(described_class.enforced_for?(project)).to be(false)
      end

      it 'ignores a stray namespace toggle' do
        stub_ee_application_setting(dependency_firewall_enabled: false)
        root_group.namespace_settings.update!(dependency_firewall_enabled: true)

        expect(described_class.enforced_for?(project)).to be(false)
      end
    end

    context 'with a nil container' do
      it 'is false even when the flag is enabled globally' do
        expect(described_class.enforced_for?(nil)).to be(false)
      end
    end
  end
end
