# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Admin::SidekiqQueues::DeleteJobs, feature_category: :sidekiq do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }

  let(:current_user) { admin }
  let(:mutation) { described_class.new(object: nil, context: query_context(user: current_user), field: nil) }

  describe '#ready?' do
    subject(:ready) { mutation.ready?(queue_name: 'authorized_projects') }

    context 'when the admin is in admin mode', :enable_admin_mode do
      it 'does not raise an error' do
        expect { ready }.not_to raise_error
      end
    end

    context 'when the admin is not in admin mode' do
      it 'raises a resource not available error' do
        expect { ready }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable,
          'You must be an admin to use this mutation')
      end
    end

    context 'when there is no current user' do
      let(:current_user) { nil }

      it 'raises a resource not available error' do
        expect { ready }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable,
          'You must be an admin to use this mutation')
      end
    end
  end
end
