# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ReferenceLimits, feature_category: :ai_catalog_curation do
  describe 'MAX_REFERENCES_PER_KIND' do
    it 'is frozen' do
      expect(described_class::MAX_REFERENCES_PER_KIND).to be_frozen
    end

    it 'sets the agent limit to 20' do
      expect(described_class::MAX_REFERENCES_PER_KIND[:agent]).to eq(20)
    end
  end

  describe 'MAX_PAYLOAD_SIZE_PER_KIND' do
    it 'is frozen' do
      expect(described_class::MAX_PAYLOAD_SIZE_PER_KIND).to be_frozen
    end

    it 'keeps every kind under the 128 KiB Linux environment variable limit' do
      described_class::MAX_PAYLOAD_SIZE_PER_KIND.each_value do |ceiling|
        expect(ceiling).to be < 128.kilobytes
      end
    end
  end

  describe '.limit_for' do
    it 'returns the limit for a known kind' do
      expect(described_class.limit_for(:agent)).to eq(20)
    end

    it 'raises KeyError for an unknown kind' do
      expect { described_class.limit_for(:mcp_server) }.to raise_error(KeyError)
    end
  end

  describe '.count_exceeded?' do
    it 'returns false at the limit' do
      expect(described_class.count_exceeded?(:agent, 20)).to be(false)
    end

    it 'returns true above the limit' do
      expect(described_class.count_exceeded?(:agent, 21)).to be(true)
    end

    it 'returns false for zero references' do
      expect(described_class.count_exceeded?(:agent, 0)).to be(false)
    end
  end

  describe '.max_payload_size_for' do
    it 'returns the ceiling for a known kind' do
      expect(described_class.max_payload_size_for(:agent)).to eq(112.kilobytes)
    end

    it 'raises KeyError for an unknown kind' do
      expect { described_class.max_payload_size_for(:mcp_server) }.to raise_error(KeyError)
    end
  end

  describe '.payload_size_exceeded?' do
    let(:agent_ceiling) { described_class.max_payload_size_for(:agent) }

    it 'returns false at the ceiling' do
      expect(described_class.payload_size_exceeded?(:agent, agent_ceiling)).to be(false)
    end

    it 'returns true above the ceiling' do
      expect(described_class.payload_size_exceeded?(:agent, agent_ceiling + 1)).to be(true)
    end

    it 'returns false for an empty payload' do
      expect(described_class.payload_size_exceeded?(:agent, 0)).to be(false)
    end

    it 'raises KeyError for an unknown kind' do
      expect { described_class.payload_size_exceeded?(:mcp_server, 1) }.to raise_error(KeyError)
    end
  end

  describe 'sizing model' do
    let(:assumed_system_prompt_length) { 10_000 }
    let(:max_description_length) { 1_024 }

    def agent_entry(id, prompt_length:, description_length:)
      {
        item_id: id.to_s,
        version: '1.2.3',
        name: format('agent-%04d', id),
        description: 'd' * description_length,
        system_prompt: 'p' * prompt_length,
        toolset: Array.new(10) { |i| "tool_#{i}" }
      }
    end

    def payload_bytesize(count, prompt_length: assumed_system_prompt_length, description_length: max_description_length)
      entries = Array.new(count) do |i|
        agent_entry(i, prompt_length: prompt_length, description_length: description_length)
      end

      entries.to_json.bytesize
    end

    it 'serializes one maximum-size agent to about 11 KB' do
      expect(payload_bytesize(1)).to be_between(10.kilobytes, 12.kilobytes)
    end

    it 'accepts ten maximum-size agents' do
      expect(described_class.payload_size_exceeded?(:agent, payload_bytesize(10))).to be(false)
    end

    it 'rejects eleven maximum-size agents' do
      expect(described_class.payload_size_exceeded?(:agent, payload_bytesize(11))).to be(true)
    end

    it 'rejects the full count of twenty maximum-size agents' do
      expect(described_class.payload_size_exceeded?(:agent, payload_bytesize(20))).to be(true)
    end

    it 'accepts the full count of twenty typical agents' do
      bytesize = payload_bytesize(20, prompt_length: 2_000, description_length: 200)

      expect(described_class.payload_size_exceeded?(:agent, bytesize)).to be(false)
    end

    it 'accepts one agent whose prompt fills the whole definition size limit' do
      bytesize = payload_bytesize(1, prompt_length: Ai::Catalog::ItemVersion::DEFINITION_SIZE_LIMIT)

      expect(described_class.payload_size_exceeded?(:agent, bytesize)).to be(false)
    end

    it 'rejects two agents whose prompts fill the whole definition size limit' do
      bytesize = payload_bytesize(2, prompt_length: Ai::Catalog::ItemVersion::DEFINITION_SIZE_LIMIT)

      expect(described_class.payload_size_exceeded?(:agent, bytesize)).to be(true)
    end

    it 'keeps the ceiling under the 128 KiB Linux limit even with maximum headroom used' do
      # A payload that passes the check must still fit in one
      # environment variable with the variable name included.
      expect(described_class.max_payload_size_for(:agent) + 'DUO_WORKFLOW_AI_CATALOG_AGENTS='.bytesize)
        .to be < 128.kilobytes
    end
  end
end
