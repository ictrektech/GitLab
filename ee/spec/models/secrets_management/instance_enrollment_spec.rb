# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::InstanceEnrollment, feature_category: :secrets_management do
  describe '.enrolled?' do
    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.enrolled?).to be true
      end
    end

    context 'when instance is not enrolled' do
      it 'returns false' do
        expect(described_class.enrolled?).to be false
      end
    end
  end

  describe '.beta?' do
    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.beta?).to be true
      end
    end

    context 'when instance is not enrolled' do
      it 'returns false' do
        expect(described_class.beta?).to be false
      end
    end
  end

  describe '.beta_enrolled?' do
    context 'when the instance is enrolled' do
      it 'returns true when the beta marker is set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: true
        )

        expect(described_class.beta_enrolled?).to be true
      end

      it 'returns false when the beta marker is not set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: false
        )

        expect(described_class.beta_enrolled?).to be false
      end

      # Pins the derivation to `.beta?` so a future GA marker only has to
      # be added there.
      it 'returns false when the instance is enrolled but no longer in beta' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: true
        )
        allow(described_class).to receive(:beta?).and_return(false)

        expect(described_class.beta_enrolled?).to be false
      end
    end

    context 'when the instance is not enrolled' do
      it 'returns false even when a stale beta marker is set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: false,
          secrets_manager_instance_beta_enrolled: true
        )

        expect(described_class.beta_enrolled?).to be false
      end
    end
  end

  describe '.add_on_requested?' do
    context 'when the instance is enrolled and the add-on intent is stamped' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_add_on_requested_at: 1.day.ago
        )
      end

      it 'returns true' do
        expect(described_class.add_on_requested?).to be true
      end
    end

    context 'when the instance is enrolled without add-on intent' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_add_on_requested_at: nil
        )
      end

      it 'returns false' do
        expect(described_class.add_on_requested?).to be false
      end
    end

    context 'when the add-on intent is stamped but the instance is not enrolled (paused)' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: false,
          secrets_manager_instance_add_on_requested_at: 1.day.ago
        )
      end

      it 'returns true' do
        expect(described_class.add_on_requested?).to be true
      end
    end
  end

  describe '.settings', :request_store do
    context 'when no settings row is persisted' do
      it 'falls back to a read-only copy of the current application settings', :aggregate_failures do
        current = Gitlab::CurrentSettings.current_application_settings
        current.secrets_manager_instance_enrolled = true

        expect(ApplicationSetting.count).to eq(0)
        expect(described_class.settings).not_to be(current)
        expect(described_class.settings).to be_readonly
        expect(described_class.enrolled?).to be true
      end

      # The fetcher's fake settings are not ActiveRecord and cannot persist,
      # so they are returned as is rather than duplicated.
      it 'returns the rake-time fake settings as is', :aggregate_failures do
        fake = Gitlab::FakeApplicationSettings.new(
          ApplicationSetting.defaults.merge(secrets_manager_instance_enrolled: true)
        )
        allow(Gitlab::CurrentSettings).to receive(:current_application_settings).and_return(fake)

        expect(described_class.settings).to be(fake)
        expect(described_class.enrolled?).to be true
      end
    end

    context 'when the settings row is persisted' do
      before do
        Gitlab::CurrentSettings.current_application_settings.save!
      end

      # Another Puma worker flipped the toggle: the row changed, but this
      # process still holds its own cached copy of the settings.
      context 'when the process-cached settings are stale' do
        before do
          stale = ApplicationSetting.current_without_cache
          allow(Gitlab::CurrentSettings).to receive(:current_application_settings).and_return(stale)

          ApplicationSetting.update_all(
            secrets_manager_instance_enrolled: true,
            secrets_manager_instance_beta_enrolled: true,
            secrets_manager_instance_add_on_requested_at: 1.day.ago
          )
        end

        it 'reads the enrollment from the row', :aggregate_failures do
          expect(Gitlab::CurrentSettings.secrets_manager_instance_enrolled).to be false
          expect(described_class.enrolled?).to be true
        end

        it 'reads the beta marker from the row', :aggregate_failures do
          expect(Gitlab::CurrentSettings.secrets_manager_instance_beta_enrolled).to be false
          expect(described_class.beta_enrolled?).to be true
        end

        it 'reads the add-on intent from the row', :aggregate_failures do
          expect(Gitlab::CurrentSettings.secrets_manager_instance_add_on_requested_at).to be_nil
          expect(described_class.add_on_requested?).to be true
        end
      end

      it 'loads only the enrollment columns, read-only', :aggregate_failures do
        recorder = ActiveRecord::QueryRecorder.new { described_class.settings }
        selected = recorder.log.first[/\ASELECT (.+?) FROM/, 1].scan(/"application_settings"\."(\w+)"/).flatten

        expect(selected).to match_array(described_class::SETTINGS_COLUMNS.map(&:to_s))
        expect(described_class.settings).to be_readonly
      end

      it 'reads the row once' do
        described_class.enrolled?

        expect do
          described_class.enrolled?
          described_class.add_on_requested?
        end.not_to exceed_query_limit(0)
      end

      it 'reads the row again after .expire_settings' do
        described_class.enrolled?
        ApplicationSetting.update_all(secrets_manager_instance_enrolled: true)

        described_class.expire_settings

        expect(described_class.enrolled?).to be true
      end
    end
  end

  describe '.stamp_add_on_intent!' do
    def requested_at
      Gitlab::CurrentSettings.secrets_manager_instance_add_on_requested_at
    end

    # Specs run with in-memory settings that are only persisted on first write;
    # production always has the row, so persist it here.
    before do
      Gitlab::CurrentSettings.current_application_settings.save!
    end

    it 'stamps once and reports later calls as not the first', :aggregate_failures do
      expect(described_class.stamp_add_on_intent!).to be true

      first_stamp = requested_at
      expect(first_stamp).to be_present

      expect(described_class.stamp_add_on_intent!).to be false
      expect(requested_at).to eq(first_stamp)
    end

    it 'is visible to a later read in the same request', :request_store do
      expect(described_class.add_on_requested?).to be false

      described_class.stamp_add_on_intent!

      expect(described_class.add_on_requested?).to be true
    end
  end

  describe '.enrollment_allowed?' do
    before do
      allow(::License).to receive(:feature_available?).and_call_original
      allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
    end

    context 'when not on GitLab.com' do
      it 'returns true' do
        expect(described_class.enrollment_allowed?).to be true
      end

      context 'when license is not available' do
        before do
          allow(::License).to receive(:feature_available?)
            .with(:native_secrets_management).and_return(false)
        end

        it 'returns false' do
          expect(described_class.enrollment_allowed?).to be false
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns false' do
        expect(described_class.enrollment_allowed?).to be false
      end
    end
  end

  describe '.offline_license?' do
    let(:online_license) { instance_double(License, online_cloud_license?: true) }
    let(:offline_license) { instance_double(License, online_cloud_license?: false) }

    where(:saas, :license, :expected) do
      [
        [false, ref(:online_license), false],
        [false, ref(:offline_license), true],
        [false, nil, true],
        [true, ref(:offline_license), false]
      ]
    end

    with_them do
      before do
        stub_saas_features(gitlab_com_subscriptions: saas)
        allow(::License).to receive(:current).and_return(license)
      end

      it 'is true unless the license can reach CustomersDot, and never on GitLab.com' do
        expect(described_class.offline_license?).to be(expected)
      end
    end
  end

  describe '.paid_experience_allowed?' do
    before do
      allow(::License).to receive(:feature_available?).and_call_original
      allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
    end

    context 'when not on GitLab.com' do
      it 'returns true' do
        expect(described_class.paid_experience_allowed?).to be true
      end

      context 'when license is not available' do
        before do
          allow(::License).to receive(:feature_available?)
            .with(:native_secrets_management).and_return(false)
        end

        it 'returns false' do
          expect(described_class.paid_experience_allowed?).to be false
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns false' do
        expect(described_class.paid_experience_allowed?).to be false
      end
    end
  end
end
