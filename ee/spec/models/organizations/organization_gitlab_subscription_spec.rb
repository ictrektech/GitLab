# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationGitlabSubscription, :saas, feature_category: :subscription_management do
  let_it_be(:organization) { create(:organization) }

  subject(:link) { build(:organization_gitlab_subscription, organization: organization) }

  describe 'associations' do
    it 'belongs to a required organization' do
      is_expected.to belong_to(:organization).class_name('Organizations::Organization')
        .inverse_of(:organization_gitlab_subscription).required
    end

    it { is_expected.to belong_to(:gitlab_subscription).inverse_of(:organization_gitlab_subscription).required }

    it 'is reachable from both the organization and the subscription' do
      persisted = create(:organization_gitlab_subscription, organization: organization)

      expect(organization.reload.organization_gitlab_subscription).to eq(persisted)
      expect(persisted.gitlab_subscription.reload.organization_gitlab_subscription).to eq(persisted)
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }

    it 'allows at most one link per organization' do
      create(:organization_gitlab_subscription, organization: organization)

      expect(link).to be_invalid
      expect(link.errors[:organization]).to include('has already been taken')
    end

    it 'allows at most one link per subscription' do
      existing = create(:organization_gitlab_subscription, organization: organization)
      duplicate = build(:organization_gitlab_subscription, gitlab_subscription: existing.gitlab_subscription)

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:gitlab_subscription]).to include('has already been taken')
    end

    it 'rejects the default organization' do
      default_organization = build(:organization)
      allow(default_organization).to receive(:default?).and_return(true)
      default_link = build(:organization_gitlab_subscription, organization: default_organization)

      expect(default_link).to be_invalid
      expect(default_link.errors[:organization]).to include("can't be the default organization")
    end
  end

  describe 'database constraints' do
    let_it_be(:existing) { create(:organization_gitlab_subscription, organization: organization) }

    it 'enforces one link per organization' do
      subscription = create(:gitlab_subscription, namespace: create(:group, organization: organization))
      duplicate = build(:organization_gitlab_subscription,
        organization: organization, gitlab_subscription: subscription)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'enforces one link per subscription' do
      duplicate = build(:organization_gitlab_subscription, gitlab_subscription: existing.gitlab_subscription)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'deletion' do
    let!(:persisted) { create(:organization_gitlab_subscription, organization: organization) }

    it 'cascades from the organization' do
      organization.delete

      expect(described_class.exists?(persisted.id)).to be(false)
    end

    it 'cascades from the subscription' do
      persisted.gitlab_subscription.delete

      expect(described_class.exists?(persisted.id)).to be(false)
    end
  end
end
