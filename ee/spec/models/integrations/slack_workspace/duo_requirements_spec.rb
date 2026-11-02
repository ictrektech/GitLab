# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::DuoRequirements, feature_category: :integrations do
  let_it_be(:group) { create(:group) }

  describe '.seats_required?' do
    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'is true with an active seat-based GitLab Duo add-on on the group' do
        create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)

        expect(described_class.seats_required?(group)).to be(true)
      end

      it 'is false for a seat-based add-on of another group' do
        create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: create(:group))

        expect(described_class.seats_required?(group)).to be(false)
      end

      it 'is false for an expired add-on' do
        create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :expired, namespace: group)

        expect(described_class.seats_required?(group)).to be(false)
      end
    end

    context 'on self-managed' do
      it 'is true with an active seat-based GitLab Duo add-on on the instance' do
        create(:gitlab_subscription_add_on_purchase, :duo_pro, :self_managed)

        expect(described_class.seats_required?(group)).to be(true)
      end

      it 'is false without one (credits only)' do
        create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed)

        expect(described_class.seats_required?(group)).to be(false)
      end
    end
  end

  describe '#checks' do
    let_it_be_with_reload(:group) { create(:group) }

    subject(:checks) { described_class.new(group).checks.index_by { |check| check[:id] } }

    def set_requirements(duo_features: true, agent_platform: true, experiment_features: true)
      group.namespace_settings
        .update!(duo_features_enabled: duo_features, experiment_features_enabled: experiment_features)
      stub_application_setting(instance_level_ai_beta_features_enabled: experiment_features)
      ::Ai::Setting.for_organization(group.organization)
        .update!(feature_settings: { duo_agent_platform_enabled: agent_platform })
      ::Ai::NamespaceSetting.find_or_initialize_by(namespace: group)
        .update!(feature_settings: { duo_agent_platform_enabled: agent_platform })
    end

    it 'lists the group settings GitLab Duo in Slack needs' do
      expect(described_class.new(group).checks.pluck(:id)).to eq(%i[duo_features agent_platform experiment_features])
    end

    shared_examples 'requirement checks' do |settings_fix|
      it 'passes every check when all settings are on' do
        set_requirements

        expect(checks.values.pluck(:ok)).to all(be(true))
      end

      %i[duo_features agent_platform experiment_features].each do |id|
        it "fails only #{id} when it is off" do
          set_requirements(id => false)

          expect(checks.transform_values { |check| check[:ok] })
            .to eq(%i[duo_features agent_platform experiment_features].index_with { |other| other != id })
        end
      end

      it 'says where to fix each check' do
        set_requirements

        expect(checks.transform_values { |check| check[:fix] }).to eq(
          duo_features: :group_settings, agent_platform: settings_fix, experiment_features: settings_fix
        )
      end
    end

    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it_behaves_like 'requirement checks', :group_settings
    end

    context 'on self-managed' do
      it_behaves_like 'requirement checks', :instance_settings
    end

    it 'fails duo_features when the group has no namespace settings' do
      group.namespace_settings.destroy!
      group.reload

      expect(checks[:duo_features][:ok]).to be(false)
    end
  end
end
