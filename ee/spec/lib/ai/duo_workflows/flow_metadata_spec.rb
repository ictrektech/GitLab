# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::DuoWorkflows::FlowMetadata, feature_category: :duo_agent_platform do
  let(:started) do
    { 'flow_id' => 'developer', 'schema_version' => 'v1', 'flow_version' => '^4.0.0',
      'flow_version_constraint' => '^4.0.0' }
  end

  describe '.started' do
    it 'records the flow and marks it as recorded by Rails' do
      json = described_class.started(flow_config_id: 'developer', flow_config_schema_version: 'v1',
        flow_version: '^4.0.0')

      expect(::Gitlab::Json::SafeParser.parse(json)).to eq(started)
    end

    it 'omits a missing schema version' do
      json = described_class.started(flow_config_id: 'chat', flow_config_schema_version: nil, flow_version: '^1.0.0')

      expect(::Gitlab::Json::SafeParser.parse(json))
        .to eq('flow_id' => 'chat', 'flow_version' => '^1.0.0', 'flow_version_constraint' => '^1.0.0')
    end

    it 'records nothing for a flow Rails does not resolve' do
      expect(described_class.started({})).to be_nil
      expect(described_class.started(nil)).to be_nil
      expect(described_class.started(flow_config_id: 'developer', flow_version: nil)).to be_nil
    end
  end

  describe '.narrowed' do
    subject(:narrowed) { described_class.narrowed(stored&.to_json, reported) }

    let(:stored) { started }
    let(:reported) { { flow_id: 'developer', schema_version: 'v1', flow_version: '4.0.0' }.to_json }

    it 'takes the reported version when it fits the constraint' do
      expect(::Gitlab::Json::SafeParser.parse(narrowed)).to eq(started.merge('flow_version' => '4.0.0'))
    end

    context 'when the session started on an exact version' do
      let(:stored) do
        started.merge('flow_version' => '2.1.0-interactive', 'flow_version_constraint' => '2.1.0-interactive')
      end

      let(:reported) { { flow_id: 'developer', schema_version: 'v1', flow_version: '2.1.0-interactive' }.to_json }

      it 'keeps that version' do
        expect(::Gitlab::Json::SafeParser.parse(narrowed)).to eq(stored)
      end
    end

    context 'when the flow has no schema version' do
      let(:stored) { { 'flow_id' => 'chat', 'flow_version' => '^1.0.0', 'flow_version_constraint' => '^1.0.0' } }
      let(:reported) { { flow_id: 'chat', flow_version: '1.2.0' }.to_json }

      it 'takes the reported version' do
        expect(::Gitlab::Json::SafeParser.parse(narrowed)).to eq(stored.merge('flow_version' => '1.2.0'))
      end
    end

    where(:case_name, :reported_metadata) do
      [
        ['a version outside the constraint', { flow_id: 'developer', schema_version: 'v1', flow_version: '9.0.0-dev' }],
        ['another flow', { flow_id: 'gitlab_duo_mention_assistant', schema_version: 'v1', flow_version: '4.0.0' }],
        ['another schema version', { flow_id: 'developer', schema_version: 'experimental', flow_version: '4.0.0' }],
        ['a version that is not a string', { flow_id: 'developer', schema_version: 'v1', flow_version: 4 }]
      ]
    end

    with_them do
      let(:reported) { reported_metadata.to_json }

      it 'keeps the recorded flow' do
        expect(narrowed).to be_nil
      end
    end

    context 'when the report is not valid JSON' do
      let(:reported) { '{not json' }

      it 'keeps the recorded flow' do
        expect(narrowed).to be_nil
      end
    end

    context 'when nothing is reported' do
      let(:reported) { nil }

      it 'keeps the recorded flow' do
        expect(narrowed).to be_nil
      end
    end

    context 'when Rails recorded no flow' do
      let(:stored) { nil }
      let(:reported) { { flow_id: 'developer', schema_version: 'v1', flow_version: '2.0.0-interactive' }.to_json }

      it 'stores the report as sent' do
        expect(narrowed).to eq(reported)
      end
    end
  end

  describe '.pinned_params' do
    it 'returns the recorded flow' do
      expect(described_class.pinned_params(started.merge('flow_version' => '4.0.0').to_json))
        .to eq(flow_config_id: 'developer', flow_config_schema_version: 'v1', flow_version: '4.0.0')
    end

    it 'returns nil for a client-only report' do
      expect(described_class.pinned_params(started.except('flow_version_constraint').to_json)).to be_nil
    end

    it 'returns nil for values that are not strings' do
      expect(described_class.pinned_params(started.merge('flow_version' => 4).to_json)).to be_nil
    end

    it 'returns nil for malformed or missing metadata' do
      expect(described_class.pinned_params('{not json')).to be_nil
      expect(described_class.pinned_params('[]')).to be_nil
      expect(described_class.pinned_params(nil)).to be_nil
    end
  end
end
