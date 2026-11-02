# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::FoundationalFlowContextBuilder, feature_category: :duo_agent_platform do
  let(:resource) { build_stubbed(:merge_request) }
  let(:fields) { { 'duo_code_review_bot_name' => 'duo-bot' } }
  let(:resolver) { ->(resource:) { fields } } # rubocop:disable Lint/UnusedBlockArgument -- matches the resolver contract
  let(:default_category) { 'agent_platform_code_review_context' }
  let(:context_category_alias) { nil }
  let(:flow) do
    Ai::Catalog::FoundationalFlow.new(
      foundational_flow_reference: 'code_review/v1',
      additional_context_resolver: resolver,
      context_category_alias: context_category_alias
    )
  end

  subject(:context) { described_class.new(flow: flow).build(resource: resource) }

  describe '#build' do
    it 'wraps the fields under the category derived from the flow reference' do
      expect(context).to contain_exactly(
        Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields)
      )
    end

    it 'calls the resolver with the resource' do
      expect(resolver).to receive(:call).with(resource: resource).and_call_original

      context
    end

    context 'when the flow sets a context_category_alias' do
      let(:context_category_alias) { 'code_review_context' }

      it 'wraps the fields under both the derived and the aliased category' do
        expect(context).to contain_exactly(
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields),
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: 'code_review_context', fields: fields)
        )
      end
    end

    context 'when the context_category_alias matches the derived category' do
      let(:context_category_alias) { default_category }

      it 'wraps the fields only once' do
        expect(context).to contain_exactly(
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields)
        )
      end
    end

    context 'when the flow has no additional_context_resolver' do
      let(:resolver) { nil }

      it { is_expected.to eq([]) }
    end

    context 'when the resolver returns no fields' do
      where(:fields) { [nil, {}] }

      with_them do
        it { is_expected.to eq([]) }
      end
    end
  end
end
