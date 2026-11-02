# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::DuoWorkflows::ContentRetention, feature_category: :duo_agent_platform do
  describe '.message' do
    it 'keeps identity, type, status and tool name, and empties the text' do
      entry = {
        'content' => 'model output', 'message_type' => 'tool', 'status' => 'success', 'role' => 'assistant',
        'message_id' => 'msg-1', 'timestamp' => 't', 'thread_ts' => 'ts-1',
        'tool_info' => { 'name' => 'read_file', 'args' => { 'path' => 'secret.rb' }, 'tool_response' => 'code' },
        'additional_context' => [{ 'id' => 'ctx-1', 'content' => 'file body' }]
      }

      expect(described_class.message(entry)).to eq(
        'message_type' => 'tool', 'status' => 'success', 'message_id' => 'msg-1', 'timestamp' => 't',
        'thread_ts' => 'ts-1', 'content' => '', 'additional_context' => nil,
        'tool_info' => { 'name' => 'read_file', 'args' => {} }
      )
    end

    it 'gives a tool entry without tool_info an empty one, and other entries none', :aggregate_failures do
      expect(described_class.message({ 'message_type' => 'tool' })['tool_info']).to eq('name' => '', 'args' => {})
      expect(described_class.message({ 'message_type' => 'agent' })['tool_info']).to be_nil
    end

    it 'is idempotent, so data Duo Workflow Service already reduced is served unchanged' do
      entry = { 'content' => 'x', 'message_type' => 'tool', 'tool_info' => { 'name' => 'n' } }
      reduced = described_class.message(entry)

      expect(described_class.message(reduced)).to eq(reduced)
    end

    it 'returns a non-message as is' do
      expect(described_class.message('not a message')).to eq('not a message')
    end
  end

  describe '.checkpoint' do
    it 'keeps only status and a reduced ui_chat_log in channel_values' do
      data = {
        'v' => 1,
        'channel_values' => {
          'status' => 'Completed',
          'plan' => { 'steps' => [] },
          'conversation_history' => { 'agent' => [] },
          'ui_chat_log' => [{ 'content' => 'model output', 'message_type' => 'agent' }]
        }
      }

      expect(described_class.checkpoint(data)).to eq(
        'v' => 1,
        'channel_values' => {
          'status' => 'Completed',
          'ui_chat_log' => [
            { 'message_type' => 'agent', 'content' => '', 'additional_context' => nil, 'tool_info' => nil }
          ]
        }
      )
    end

    it 'returns nil as is' do
      expect(described_class.checkpoint(nil)).to be_nil
    end
  end

  describe '.channel_values' do
    it 'serves channels without a ui_chat_log, or with an empty one, as they are', :aggregate_failures do
      expect(described_class.channel_values('status' => 'Completed', 'plan' => {})).to eq('status' => 'Completed')
      expect(described_class.channel_values('ui_chat_log' => nil)).to eq('ui_chat_log' => nil)
    end
  end

  describe '.checkpoint_metadata' do
    it 'drops writes and anything else that can carry node output' do
      metadata = { 'source' => 'loop', 'step' => 1, 'parents' => {}, 'writes' => { 'agent' => 'model output' } }

      expect(described_class.checkpoint_metadata(metadata)).to eq('source' => 'loop', 'step' => 1, 'parents' => {})
    end

    it 'returns nil as is' do
      expect(described_class.checkpoint_metadata(nil)).to be_nil
    end
  end

  describe '.audit_details' do
    it 'keeps only metadata fields' do
      details = { 'model_name' => 'claude', 'latency_ms' => 5, 'prompt_content' => 'p', 'goal' => 'g' }

      expect(described_class.audit_details(details)).to eq('model_name' => 'claude', 'latency_ms' => 5)
    end

    it 'keeps the policy reference and the sizes of the emptied text' do
      details = {
        'policy_ref' => 'policy', 'content_length' => 10, 'response_length' => 20,
        'prompt_content_bytes' => 30, 'prompt_content_truncated' => true,
        'response_content_bytes' => 40, 'response_content_truncated' => false
      }

      expect(described_class.audit_details(details)).to eq(details)
    end
  end
end
