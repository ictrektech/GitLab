# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::TestSelfHostedEmbeddingModelService, :aggregate_failures,
  feature_category: :global_search do
  let_it_be(:user) { create(:user) }

  let(:self_hosted_model) do
    build(:ai_self_hosted_model, :embedding, name: 'Embedding Model 1',
      identifier: 'openai/embedding-model-001')
  end

  let(:mock_ac_embedding_model) { instance_double(::ActiveContext::EmbeddingModel) }

  subject(:service) { described_class.new(self_hosted_model: self_hosted_model, user: user) }

  describe '#execute' do
    before do
      allow(mock_ac_embedding_model).to receive(:generate_embeddings).and_return([[1, 2, 3, 4]])
      allow(::ActiveContext::EmbeddingModel).to receive(:new).and_return(mock_ac_embedding_model)
    end

    it 'tests embeddings generation and returns a successful response' do
      expect(Ai::ActiveContext::Embeddings::ModelFactory)
        .to receive(:for_self_hosted_model).with(self_hosted_model).and_call_original

      expect(mock_ac_embedding_model).to receive(:generate_embeddings).with('test input', user: user)

      response = service.execute

      expect(response).to be_success
      expect(response.payload).to eq(
        tested_model_metadata: {
          model_type: Ai::ActiveContext::Embedding::MODEL_TYPE_SELF_HOSTED,
          model_ref: 'Embedding Model 1',
          dimensions: 4
        }
      )
    end

    context 'when there is an error in the embeddings request' do
      before do
        allow(mock_ac_embedding_model).to receive(:generate_embeddings).and_raise(
          StandardError, "error in embeddings generation"
        )
      end

      it 'returns an error response' do
        response = service.execute

        expect(response.error?).to be(true)
        expect(response.message).to eq("error in embeddings generation")
      end
    end

    context 'when the result is an empty array' do
      before do
        allow(mock_ac_embedding_model).to receive(:generate_embeddings).and_return([])
      end

      it 'returns an error indicating empty result' do
        response = service.execute

        expect(response.error?).to be(true)
        expect(response.message).to eq("Embeddings request returned no results.")
      end
    end

    context 'when the embeddings is empty' do
      before do
        allow(mock_ac_embedding_model).to receive(:generate_embeddings).and_return([[]])
      end

      it 'returns an error indicating empty result' do
        response = service.execute

        expect(response.error?).to be(true)
        expect(response.message).to eq("Embeddings request returned no results.")
      end
    end

    context 'when the record is not an embedding model' do
      let(:self_hosted_model) { build(:ai_self_hosted_model, :general) }

      it 'returns an error response rather than raising' do
        response = service.execute

        expect(response).to be_error
        expect(response.message).to eq("Self-hosted model must have 'embedding' family")
      end
    end
  end
end
