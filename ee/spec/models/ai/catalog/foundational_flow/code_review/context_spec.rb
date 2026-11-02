# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::CodeReview::Context, feature_category: :dap_code_review do
  describe '.call' do
    let_it_be(:merge_request) { create(:merge_request) }

    let(:review_bot) do
      ::Users::Internal.in_organization(merge_request.project.organization_id).duo_code_review_bot
    end

    subject(:context) { described_class.call(resource: resource) }

    context 'when the resource is not a merge request' do
      let(:resource) { build_stubbed(:issue) }

      it 'resolves to no context without looking the bot up' do
        expect(::Users::Internal).not_to receive(:in_organization)

        expect(context).to eq({})
      end
    end

    context 'when the resource is a merge request' do
      let(:resource) { merge_request }

      before do
        allow(merge_request).to receive(:duo_code_review_last_reviewed_head_sha)
          .with(review_bot).and_return(last_reviewed_head_sha)
      end

      context 'when the bot reviewed the merge request before' do
        let(:last_reviewed_head_sha) { 'abc123' }

        it 'returns the username of the Duo Code Review bot and the last reviewed head sha' do
          expect(context).to eq(
            "duo_code_review_bot_name" => review_bot.username,
            "last_reviewed_head_sha" => 'abc123'
          )
        end
      end

      context 'when the bot did not review the merge request before' do
        let(:last_reviewed_head_sha) { nil }

        it 'omits the last reviewed head sha' do
          expect(context).to eq("duo_code_review_bot_name" => review_bot.username)
        end
      end
    end
  end
end
