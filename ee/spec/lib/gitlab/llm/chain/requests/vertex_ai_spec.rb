# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Llm::Chain::Requests::VertexAi, feature_category: :chat_engine do
  describe 'initializer' do
    it 'initializes the vertex client' do
      request = described_class.new(double, unit_primitive: 'duo_chat')

      expect(request.ai_client.class).to eq(::Gitlab::Llm::VertexAi::Client)
    end
  end

  describe 'request' do
    it 'calls the vertex completion endpoint' do
      request = described_class.new(double, unit_primitive: 'duo_chat')
      ai_client = double
      allow(request).to receive(:ai_client).and_return(ai_client)
      expect(ai_client).to receive(:text)

      request.request({ prompt: "some user request", options: {} })
    end
  end
end
