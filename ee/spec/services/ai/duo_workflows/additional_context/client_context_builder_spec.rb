# frozen_string_literal: true

require 'fast_spec_helper'
require 'json_schemer'
require_relative '../../../../../app/services/ai/duo_workflows/additional_context/client_context_builder'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::ClientContextBuilder, feature_category: :duo_agent_platform do
  let(:schema_path) do
    Rails.root.join('app/validators/json_schemas/agent_platform/agent_platform_client_context/1.0.0.json')
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  subject(:fields) { described_class.build(content: content) }

  context 'with content' do
    let(:content) { "You were mentioned in a Slack thread.\n\n<conversation>\nhi\n</conversation>" }

    it 'builds the content field' do
      expect(fields).to eq('content' => content)
    end

    it 'is valid against the schema' do
      expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
    end
  end

  context 'with blank content' do
    let(:content) { '' }

    it { is_expected.to be_nil }
  end

  describe 'schema' do
    it 'rejects missing content and unknown fields', :aggregate_failures do
      expect(schema.valid?({})).to be(false)
      expect(schema.valid?({ 'content' => 'x', 'extra' => 'y' })).to be(false)
    end
  end
end
