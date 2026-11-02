# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::AddOnPurchases::SelfManaged::ProvisionServices::OrbitPromo,
  :freeze_time, feature_category: :'add-on_provisioning' do
  describe '#execute' do
    include_context 'with provision services common setup'

    let_it_be(:add_on_orbit_promo) { create(:gitlab_subscription_add_on, :orbit_promo) }
    let_it_be(:add_on_self_hosted_dap) { create(:gitlab_subscription_add_on, :self_hosted_dap) }

    describe 'delegations' do
      subject { provision_service }

      it_behaves_like 'delegates add_on params to license_add_on'
    end

    context 'without Orbit Promo' do
      let(:add_ons) { [] }

      it 'does not create an Orbit Promo add-on purchase' do
        expect { provision_service.execute }.not_to change { GitlabSubscriptions::AddOnPurchase.count }
      end
    end

    context 'with Orbit Promo' do
      let(:add_ons) { %i[orbit_promo] }

      it 'creates a new Orbit Promo add-on purchase' do
        expect do
          provision_service.execute
        end.to change { GitlabSubscriptions::AddOnPurchase.count }.from(0).to(1)

        expect(GitlabSubscriptions::AddOnPurchase.first).to have_attributes(
          subscription_add_on_id: add_on_orbit_promo.id,
          quantity: quantity,
          started_at: started_at,
          expires_on: started_at + 1.year,
          purchase_xid: purchase_xid,
          trial: trial
        )
      end
    end

    context 'with Orbit Promo in a legacy license' do
      let(:add_ons) { %i[orbit_promo] }
      let(:cloud_licensing_enabled) { false }
      let(:offline_cloud_licensing_enabled) { false }

      it 'creates an Orbit Promo add-on purchase' do
        expect { provision_service.execute }
          .to change { GitlabSubscriptions::AddOnPurchase.for_orbit_promo.count }.by(1)
      end

      context 'when the license no longer includes Orbit Promo' do
        let(:add_ons) { [] }
        let!(:existing_orbit_promo) do
          create(
            :gitlab_subscription_add_on_purchase,
            add_on: add_on_orbit_promo,
            quantity: quantity,
            namespace: nil
          )
        end

        it 'expires the existing Orbit Promo add-on purchase' do
          provision_service.execute

          expect(existing_orbit_promo.reload.expires_on).to eq(Date.yesterday)
        end
      end
    end

    context 'with existing Orbit Promo' do
      let(:add_ons) { %i[orbit_promo] }

      context 'when expired' do
        let!(:existing_orbit_promo) do
          create(
            :gitlab_subscription_add_on_purchase,
            add_on: add_on_orbit_promo,
            quantity: quantity,
            started_at: 2.years.ago,
            expires_on: 1.year.ago,
            namespace: namespace
          )
        end

        it 'updates existing add-on purchase', :aggregate_failures do
          expect do
            provision_service.execute
          end.not_to change { GitlabSubscriptions::AddOnPurchase.count }

          expect(existing_orbit_promo.reload.started_at).to eq(started_at)
          expect(existing_orbit_promo.expires_on).to eq(started_at + 1.year)
        end
      end

      context 'with an additional add-on purchase' do
        let(:add_ons) { %i[orbit_promo self_hosted_dap] }

        let!(:existing_orbit_promo) do
          create(
            :gitlab_subscription_add_on_purchase,
            add_on: add_on_orbit_promo,
            quantity: quantity,
            namespace: nil
          )
        end

        it 'does not affect the Orbit Promo purchase', :aggregate_failures do
          expect { provision_service.execute }.not_to change { GitlabSubscriptions::AddOnPurchase.count }

          expect(GitlabSubscriptions::AddOnPurchase.first).to have_attributes(
            subscription_add_on_id: add_on_orbit_promo.id,
            quantity: quantity,
            started_at: started_at,
            expires_on: started_at + 1.year,
            purchase_xid: purchase_xid,
            trial: trial
          )
        end
      end
    end

    context 'with existing Self-Hosted DAP' do
      let(:existing_add_on_attrs) do
        {
          quantity: 1,
          started_at: 1.day.ago.to_date,
          expires_on: (1.day.ago + 1.year).to_date,
          namespace: namespace,
          trial: trial
        }
      end

      let!(:existing_self_hosted_dap) do
        create(:gitlab_subscription_add_on_purchase,
          existing_add_on_attrs.merge(
            add_on: add_on_self_hosted_dap,
            purchase_xid: '987654321'
          )
        )
      end

      context 'with additional purchase of Orbit Promo' do
        let(:add_ons) { %i[self_hosted_dap orbit_promo] }

        it 'does not affect the existing add-on purchase', :aggregate_failures do
          expect do
            provision_service.execute
          end.to change { GitlabSubscriptions::AddOnPurchase.count }.from(1).to(2)

          existing_self_hosted_dap.reload

          expect(existing_self_hosted_dap).to have_attributes(
            existing_add_on_attrs.merge(subscription_add_on_id: add_on_self_hosted_dap.id, purchase_xid: '987654321')
          )
        end
      end
    end
  end
end
