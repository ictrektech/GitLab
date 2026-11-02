# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::UpdateService, feature_category: :webhooks do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:hook) { create(:project_hook, project: project, url: 'https://example.com/old') }
  let(:hook_params) { { url: 'https://example.com/new', push_events: false } }

  subject(:service) { described_class.new(user) }

  describe '#execute' do
    context 'when the user does not have permission' do
      it 'is an error and does not change the hook' do
        response = service.execute(hook, hook_params)

        expect(response).to be_error
        expect(response).to have_attributes(message: described_class::DENIED, http_status: 403)
        expect(hook.reload.url).to eq('https://example.com/old')
      end
    end

    context 'when the user has permission' do
      before_all do
        project.add_maintainer(user)
      end

      it 'updates the hook and returns it', :aggregate_failures do
        response = service.execute(hook, hook_params)

        expect(response).to be_success
        expect(response[:hook]).to eq(hook)
        expect(hook.reload).to have_attributes(url: 'https://example.com/new', push_events: false)
      end

      context 'when the URL is invalid' do
        let(:hook_params) { { url: 'invalid_url' } }

        it 'returns an error response' do
          response = service.execute(hook, hook_params)

          expect(response).to be_error
          expect(response).to have_attributes(message: 'Invalid url given', http_status: 422)
        end
      end

      context 'when the branch filter is invalid' do
        let(:hook_params) { { push_events_branch_filter: 'bad branch name' } }

        it 'returns an error response' do
          response = service.execute(hook, hook_params)

          expect(response).to be_error
          expect(response).to have_attributes(message: 'Invalid branch filter given', http_status: 422)
        end
      end

      context 'when custom headers are invalid' do
        let(:hook_params) { { custom_headers: { 'bad header' => 'value' } } }

        it 'returns an error response' do
          response = service.execute(hook, hook_params)

          expect(response).to be_error
          expect(response.message).to start_with('Custom headers validation failed:')
          expect(response.http_status).to eq(422)
        end
      end

      context 'when another validation fails' do
        let(:hook_params) { { name: 'a' * 256 } }

        it 'returns the full error messages flagged as a generic validation failure' do
          response = service.execute(hook, hook_params)

          expect(response).to be_error
          expect(response.message).to include('Name')
          expect(response.http_status).to eq(422)
          expect(response.reason).to eq(WebHooks::ValidationErrors::GENERIC_VALIDATION_FAILURE)
        end
      end
    end
  end
end
