# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskContribution'], feature_category: :code_review_workflow do
  include GraphqlHelpers

  subject { described_class }

  it { is_expected.to have_graphql_fields(:kind, :identifier, :description, :evidence, :contribution) }

  it 'accepts :ai_workflows in its own object-level authorization scopes' do
    expect(described_class.authorization_scopes).to include(:ai_workflows)
  end

  describe 'field resolution' do
    let(:row) { { 'signal' => 'test_coverage.uncovered_lines', 'contribution' => 10.0, 'detail' => 'Two files' } }

    it 'reads identifier, evidence and contribution from the signal_breakdown row' do
      expect(resolve_field(:identifier, row)).to eq('test_coverage.uncovered_lines')
      expect(resolve_field(:evidence, row)).to eq('Two files')
      expect(resolve_field(:contribution, row)).to eq(10.0)
    end

    context 'when the identifier is a registered signal' do
      it 'resolves kind as signal' do
        expect(resolve_field(:kind, row)).to eq('signal')
      end

      it 'resolves the description from the registered signal class' do
        expect(resolve_field(:description, row)).to eq('Uncovered changed lines')
      end
    end

    context 'when the identifier is a risk domain' do
      let(:row) { { 'signal' => 'authorization', 'contribution' => 21.0, 'detail' => 'authorization: true' } }

      it 'resolves kind as domain' do
        expect(resolve_field(:kind, row)).to eq('domain')
      end

      it 'resolves the description from the domain catalog' do
        expect(resolve_field(:description, row))
          .to eq(::Gitlab::Duo::RiskAssessment::Domain.description_for('authorization'))
      end
    end

    context 'when the identifier matches neither a registered signal nor a risk domain' do
      let(:row) { { 'signal' => 'unknown_key', 'contribution' => 1.0 } }

      it 'resolves kind as signal' do
        expect(resolve_field(:kind, row)).to eq('signal')
      end

      it 'resolves the description as the key' do
        expect(resolve_field(:description, row)).to eq('unknown_key')
      end
    end
  end
end
