# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a self-hosted model', feature_category: :"self-hosted_models" do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:admin) }
  let_it_be(:license) { create(:license, plan: License::ULTIMATE_PLAN) }
  let_it_be(:add_on_purchase) do
    create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :active, :self_managed)
  end

  let(:input) do
    {
      "name" => 'ollama1-mistral',
      "endpoint" => 'http://localhost:8080',
      "model" => 'MISTRAL',
      "api_token" => "test_api_token",
      "identifier" => "provider/some-model",
      "provider" => 'API'
    }
  end

  let(:mutation) { graphql_mutation(:ai_self_hosted_model_create, input) }
  let(:mutation_response) { graphql_mutation_response(:ai_self_hosted_model_create) }

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  shared_examples 'it calls the manage_ai_settings policy' do
    it 'calls the manage_self_hosted_models_settings policy' do
      allow(::Ability).to receive(:allowed?).and_call_original
      expect(::Ability).to receive(:allowed?).with(current_user, :manage_self_hosted_models_settings)

      request
    end
  end

  context 'when user is not allowed to write changes' do
    let(:current_user) { create(:user) }

    it_behaves_like 'it calls the manage_ai_settings policy'
    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when user is allowed to write changes' do
    it_behaves_like 'it calls the manage_ai_settings policy'

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_ai_self_hosted_model do
      let(:user) { current_user }
      let(:boundary_object) { :instance }
      let(:authz_mutation) { graphql_mutation(:ai_self_hosted_model_create, input, 'errors') }
      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end

    context 'when there are errors with creating the self-hosted model' do
      let(:input) do
        {
          "name" => '',
          "endpoint" => 'http://localhost:8080',
          "model" => 'MISTRAL',
          "api_token" => "test_api_token",
          "provider" => 'API'
        }
      end

      it 'returns an error message' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['selfHostedModel']).to be_nil
        expect(mutation_response['errors']).to include("Name can't be blank")
      end

      it 'does not create a self-hosted model' do
        expect { request }.not_to change { ::Ai::SelfHostedModel.count }
      end
    end

    context 'with an IAM role' do
      let(:input) do
        {
          "name" => 'bedrock-claude',
          "model" => 'CLAUDE_3',
          "identifier" => "bedrock/anthropic.claude-3-haiku-20240307-v1:0",
          "provider" => 'BEDROCK',
          "iam_role" => iam_role
        }.merge(extra_input)
      end

      let(:extra_input) { {} }

      context 'when the role is a valid ARN' do
        let(:iam_role) { 'arn:aws:iam::123456789012:role/my-role' }

        it 'persists the IAM role' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['selfHostedModel']).to include('iamRole' => iam_role)
          expect(::Ai::SelfHostedModel.last.iam_role).to eq(iam_role)
        end
      end

      context 'when an API key is also given' do
        let(:iam_role) { 'arn:aws:iam::123456789012:role/my-role' }
        let(:extra_input) { { "api_token" => 'test_api_token' } }

        it 'returns an error' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['selfHostedModel']).to be_nil
          expect(mutation_response['errors'].join).to include('cannot be set together with an API key')
        end
      end

      context 'when the role is not a valid ARN' do
        let(:iam_role) { 'not-an-arn' }

        it 'returns an error' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['selfHostedModel']).to be_nil
          expect(mutation_response['errors'].join).to include('Iam role must be a valid IAM role ARN')
        end
      end
    end

    context 'when there are no errors' do
      let(:expected_result) do
        {
          "name" => 'ollama1-mistral',
          "endpoint" => 'http://localhost:8080',
          "model" => 'mistral',
          "hasApiToken" => true,
          "identifier" => "provider/some-model",
          "provider" => 'API'
        }
      end

      it 'creates a self-hosted model' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['selfHostedModel']).to include(**expected_result)
      end
    end
  end
end
