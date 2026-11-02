# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::AddOnPurchases::OfflineCloudLicenseProvisionWorker, :without_license, feature_category: :subscription_management do
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it { is_expected.to include_module(ApplicationWorker) }
  it { is_expected.to include_module(CronjobQueue) }
  it { expect(described_class.get_feature_category).to eq(:"add-on_provisioning") }

  describe '#perform' do
    subject(:perform) { described_class.new.perform }

    let_it_be(:organization) { create(:organization) }
    let_it_be(:restrictions) do
      {
        subscription_id: "0000001",
        subscription_name: "SUB-001",
        add_on_products: {
          duo_pro: [
            {
              quantity: 1,
              started_on: Date.current.to_s,
              expires_on: 1.year.from_now.to_date.to_s,
              purchase_xid: "A-S000001",
              trial: false
            }
          ]
        }
      }
    end

    let(:gitlab_license) { build(:gitlab_license, :offline, restrictions: restrictions) }
    let!(:license) { create(:license, data: gitlab_license.export) }
    let(:execution_log) do
      {
        message: 'Offline/Legacy license checked for potentially new add-on purchases',
        license_type: 'offline_cloud',
        response: {
          add_on_purchases: [kind_of(GitlabSubscriptions::AddOnPurchase)],
          http_status: :ok,
          message: 'Successfully processed add-ons',
          reason: nil,
          status: :success
        },
        subscription_id: license.subscription_id,
        subscription_name: license.subscription_name
      }
    end

    it_behaves_like 'an idempotent worker'

    it 'provisions add-on purchases' do
      expect { perform }.to change { GitlabSubscriptions::AddOnPurchase.count }.by(1)
    end

    it 'expires the cached current license before reading it' do
      expect(License).to receive(:reset_current).ordered.and_call_original
      expect(License).to receive(:current).at_least(:once).ordered.and_call_original

      perform
    end

    it 'provisions against the current license instead of a stale cached one' do
      license_without_addon = create(:license, data: build(:gitlab_license, :offline, restrictions: {
        subscription_id: '0000001',
        subscription_name: 'SUB-001'
      }).export)

      License.current

      create(:license, data: build(:gitlab_license, :offline, restrictions: {
        subscription_id: '0000001',
        subscription_name: 'SUB-001',
        add_on_products: {
          duo_pro: [
            {
              quantity: 1,
              started_on: Date.current.to_s,
              expires_on: 1.year.from_now.to_date.to_s,
              purchase_xid: 'A-S000001',
              trial: false
            }
          ]
        }
      }).export)

      # Simulate a *different* Sidekiq process that never saw the license with
      # add-on's after_commit: re-seed the process cache so License.current would
      # return the license without the add-on again.
      License.cache.write(License::CACHE_KEY, license_without_addon)

      expect(License.current.id).to eq(license_without_addon.id)

      expect { described_class.new.perform }
        .to change { GitlabSubscriptions::AddOnPurchase.for_self_managed.count }.by(1)
    end

    it { is_expected.to be_present }

    it 'logs execution' do
      expect(Gitlab::AppLogger).to receive(:info).with(execution_log)

      perform
    end

    shared_examples 'does nothing' do
      it 'provisions no add-on purchases' do
        expect { perform }.not_to change { GitlabSubscriptions::AddOnPurchase.count }
      end

      it { is_expected.to be_nil }

      it 'does not log execution' do
        expect(Gitlab::AppLogger).not_to receive(:info)

        perform
      end
    end

    context 'without license' do
      let(:license) { nil }

      it_behaves_like 'does nothing'
    end

    context 'with online license' do
      let(:gitlab_license) { build(:gitlab_license, :online, restrictions: restrictions) }

      it_behaves_like 'does nothing'
    end

    context 'with legacy license' do
      # Only the Orbit promo add-on is read from a legacy license; other add-ons stay cloud-license only.
      let(:gitlab_license) { build(:gitlab_license, :legacy, restrictions: restrictions) }

      it 'provisions no add-on purchases other than Orbit promo' do
        expect(GitlabSubscriptions::AddOnPurchases::SelfManaged::ProvisionServices::AddOns).not_to receive(:new)

        expect { perform }.not_to change { GitlabSubscriptions::AddOnPurchase.count }
      end

      context 'with an Orbit promo add-on' do
        let_it_be(:orbit_promo_add_on) { create(:gitlab_subscription_add_on, :orbit_promo) }
        let(:restrictions) do
          {
            add_on_products: {
              orbit_promo: [
                {
                  quantity: 1,
                  started_on: Date.current.to_s,
                  expires_on: 1.year.from_now.to_date.to_s,
                  purchase_xid: 'A-S000002',
                  trial: false
                }
              ]
            }
          }
        end

        it 'provisions the Orbit promo add-on purchase' do
          expect { perform }.to change { GitlabSubscriptions::AddOnPurchase.for_orbit_promo.count }.by(1)
        end
      end
    end
  end
end
