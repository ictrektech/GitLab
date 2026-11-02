# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Session, feature_category: :compliance_management do
  subject(:session) { build(:ai_compliance_anthropic_session) }

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).class_name('::Group').required }
    it { is_expected.to belong_to(:anthropic_integration).class_name('::Ai::Compliance::Anthropic::Integration').required }
    it { is_expected.to belong_to(:ai_governance_session).class_name('::Ai::Governance::Session').required }
  end

  describe 'validations' do
    subject(:session) { create(:ai_compliance_anthropic_session) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:session_xid) }
    it { is_expected.to validate_length_of(:session_xid).is_at_most(255) }
    it { is_expected.to validate_length_of(:message_watermark).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:ai_governance_session_id) }

    it 'allows the same session id twice in one namespace' do
      duplicate = build(:ai_compliance_anthropic_session,
        namespace: session.namespace,
        anthropic_integration: session.anthropic_integration,
        session_xid: session.session_xid,
        ai_governance_session: create(:ai_governance_session, :external, namespace: session.namespace))

      expect(duplicate).to be_valid
    end

    it 'is invalid when the namespace differs from the integration namespace' do
      session.namespace = create(:group)

      expect(session).not_to be_valid
      expect(session.errors[:namespace]).to include(_('must match the Anthropic Compliance integration namespace'))
    end

    it 'is valid when the governance session is in the same namespace' do
      expect(session.ai_governance_session.namespace_id).to eq(session.namespace_id)
      expect(session).to be_valid
    end

    it 'is invalid when the governance session belongs to another namespace' do
      session.ai_governance_session = create(:ai_governance_session, :external)

      expect(session).not_to be_valid
      expect(session.errors[:namespace]).to include(_('must match the AI governance session namespace'))
    end
  end

  describe 'sharding key' do
    let(:integration) { build_stubbed(:ai_compliance_anthropic_integration) }

    subject(:session) { described_class.new(anthropic_integration: integration) }

    it { is_expected.to populate_sharding_key(:namespace_id).with(integration.namespace_id) }
  end

  describe 'database constraints' do
    it 'rejects a second row for the same governance session' do
      existing = create(:ai_compliance_anthropic_session)
      duplicate = build(:ai_compliance_anthropic_session,
        namespace: existing.namespace,
        anthropic_integration: existing.anthropic_integration,
        ai_governance_session: existing.ai_governance_session)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'is deleted with its governance session' do
      session = create(:ai_compliance_anthropic_session)

      expect { session.ai_governance_session.delete }.to change { described_class.count }.by(-1)
    end

    it 'is deleted with its integration' do
      session = create(:ai_compliance_anthropic_session)

      expect { session.anthropic_integration.delete }.to change { described_class.count }.by(-1)
    end
  end
end
