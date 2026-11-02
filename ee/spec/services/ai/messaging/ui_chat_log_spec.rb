# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::UiChatLog, feature_category: :duo_agent_platform do
  let(:reader) { Class.new { include Ai::Messaging::UiChatLog }.new }

  def todo_write(todos)
    { 'tool_info' => { 'name' => 'todo_write', 'args' => { 'todos' => todos } } }
  end

  describe '#latest_todos' do
    it 'returns the todos from the most recent todo_write call, in order' do
      messages = [
        todo_write([{ 'description' => 'Old', 'status' => 'completed' }]),
        todo_write([
          { 'description' => 'First', 'status' => 'completed' },
          { 'description' => 'Second', 'status' => 'in_progress' }
        ])
      ]

      expect(reader.latest_todos(messages)).to eq([
        { 'description' => 'First', 'status' => 'completed' },
        { 'description' => 'Second', 'status' => 'in_progress' }
      ])
    end

    it 'ignores tool calls that are not todo_write' do
      messages = [{ 'tool_info' => { 'name' => 'read_file', 'args' => { 'todos' => [{ 'description' => 'No' }] } } }]

      expect(reader.latest_todos(messages)).to be_empty
    end

    # tool_info is absent on plain agent messages and has been seen as a string.
    it 'returns nothing when no message carries a tool_info hash' do
      messages = [{ 'message_type' => 'agent', 'content' => 'hi' }, { 'tool_info' => 'not a hash' }]

      expect(reader.latest_todos(messages)).to be_empty
    end
  end

  describe '#latest_agent_content' do
    it 'returns the most recent non-blank agent message unchanged' do
      messages = [
        { 'message_type' => 'agent', 'content' => 'First' },
        { 'message_type' => 'user', 'content' => 'Ignored' },
        { 'message_type' => 'agent', 'content' => "**Latest**\n\nstep" },
        { 'message_type' => 'agent', 'content' => '' }
      ]

      expect(reader.latest_agent_content(messages)).to eq("**Latest**\n\nstep")
    end

    it 'returns nil when the agent has said nothing' do
      expect(reader.latest_agent_content([{ 'message_type' => 'user', 'content' => 'hi' }])).to be_nil
    end
  end

  describe '#renders_progress?' do
    it 'is true for an agent message with content' do
      expect(reader.renders_progress?({ 'message_type' => 'agent', 'content' => 'Looking' })).to be(true)
    end

    it 'is true for a todo_write call' do
      expect(reader.renders_progress?(todo_write([]))).to be(true)
    end

    it 'is false for an agent message without content' do
      expect(reader.renders_progress?({ 'message_type' => 'agent', 'content' => '' })).to be(false)
    end

    it 'is false for any other tool call' do
      expect(reader.renders_progress?({ 'tool_info' => { 'name' => 'read_file' } })).to be_falsey
    end

    it 'is false when tool_info is not a hash' do
      expect(reader.renders_progress?({ 'tool_info' => 'not a hash' })).to be(false)
    end

    it 'is false for a user message' do
      expect(reader.renders_progress?({ 'message_type' => 'user', 'content' => 'hi' })).to be(false)
    end
  end
end
