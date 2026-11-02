# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FoundationalAgents::EnabledResolver, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  describe '#enabled?' do
    subject(:enabled) do
      described_class.new(default_enabled: default_enabled, gated_by_switch: gated_by_switch).enabled?(agent_setting)
    end

    context 'when the switch gates every agent' do
      let(:gated_by_switch) { true }

      where(:default_enabled, :agent_setting, :expected) do
        true  | nil   | true
        true  | true  | true
        true  | false | false
        false | nil   | false
        false | true  | false
        false | false | false
      end

      with_them do
        it { is_expected.to be(expected) }
      end
    end

    context 'when an agent setting overrides the switch' do
      let(:gated_by_switch) { false }

      where(:default_enabled, :agent_setting, :expected) do
        true  | nil   | true
        true  | true  | true
        true  | false | false
        false | nil   | false
        false | true  | true
        false | false | false
      end

      with_them do
        it { is_expected.to be(expected) }
      end
    end
  end

  describe '.for' do
    subject(:resolver) { described_class.for(container) }

    before do
      allow(container).to receive(:foundational_agents_default_enabled).and_return(false)
    end

    context 'with a top-level group' do
      let(:container) { build_stubbed(:group) }

      it 'gates every agent by the switch' do
        expect(resolver.enabled?(true)).to be(false)
      end

      context 'when the group readiness card is off' do
        before do
          stub_feature_flags(duo_group_agent_readiness_settings: false)
        end

        it 'lets an agent setting override the switch' do
          expect(resolver.enabled?(true)).to be(true)
        end
      end
    end

    context 'with an organization' do
      let(:container) { build_stubbed(:organization) }

      it 'lets an agent setting override the switch' do
        expect(resolver.enabled?(true)).to be(true)
      end
    end
  end
end
