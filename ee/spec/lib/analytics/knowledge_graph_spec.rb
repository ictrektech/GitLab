# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph, feature_category: :knowledge_graph do
  using RSpec::Parameterized::TableSyntax

  describe '.service_configured?' do
    subject(:configured) { described_class.service_configured? }

    context 'when knowledge_graph.enabled is true' do
      before do
        stub_config(knowledge_graph: { 'enabled' => true })
      end

      it { is_expected.to be(true) }
    end

    context 'when knowledge_graph.enabled is false' do
      before do
        stub_config(knowledge_graph: { 'enabled' => false })
      end

      it { is_expected.to be(false) }
    end

    context 'when knowledge_graph.enabled key is absent' do
      before do
        stub_config(knowledge_graph: {})
      end

      it 'coerces the nil to a strict boolean false' do
        is_expected.to be(false)
      end
    end

    context 'when knowledge_graph config section is missing' do
      before do
        allow(Gitlab.config).to receive(:knowledge_graph).and_raise(Gitlab::Configs::MissingConfig)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '.enabled_for?' do
    let_it_be(:user) { create(:user) }

    subject(:enabled) { described_class.enabled_for?(user) }

    where(:service_configured, :expected) do
      true  | true
      false | false
    end

    with_them do
      before do
        stub_config(knowledge_graph: { 'enabled' => service_configured })
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '.accessible_for?' do
    let_it_be(:user) { create(:user) }

    subject(:accessible) { described_class.accessible_for?(user) }

    before do
      stub_config(knowledge_graph: { 'enabled' => true })
      allow(::Analytics::KnowledgeGraph::OrbitLicense).to receive(:available_for?).with(user).and_return(license)
    end

    context 'when enabled and licensed' do
      let(:license) { true }

      it { is_expected.to be(true) }
    end

    context 'when enabled but not licensed' do
      let(:license) { false }

      it { is_expected.to be(false) }
    end

    context 'when licensed but the service is not configured' do
      let(:license) { true }

      before do
        stub_config(knowledge_graph: { 'enabled' => false })
      end

      it 'does not check the license' do
        expect(::Analytics::KnowledgeGraph::OrbitLicense).not_to receive(:available_for?)

        is_expected.to be(false)
      end
    end
  end

  describe '.status_accessible_for_request?', :request_store do
    let_it_be(:user) { create(:user) }
    let_it_be(:other_user) { create(:user) }

    before do
      allow(described_class).to receive(:enabled_for?).and_return(true)
    end

    it 'checks status access once per user in a request' do
      expect(::Analytics::KnowledgeGraph::OrbitLicense)
        .to receive(:status_available_for?).with(user).once.and_return(true)
      expect(::Analytics::KnowledgeGraph::OrbitLicense)
        .to receive(:status_available_for?).with(other_user).once.and_return(false)

      2.times do
        expect(described_class.status_accessible_for_request?(user)).to be(true)
        expect(described_class.status_accessible_for_request?(other_user)).to be(false)
      end
    end

    it 'is false without checking the license when the service is not configured' do
      allow(described_class).to receive(:enabled_for?).with(user).and_return(false)
      expect(::Analytics::KnowledgeGraph::OrbitLicense).not_to receive(:status_available_for?)

      expect(described_class.status_accessible_for_request?(user)).to be(false)
    end

    it 'is false without a user' do
      expect(described_class.status_accessible_for_request?(nil)).to be(false)
    end
  end
end
