# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::NotesCreateRateLimit, feature_category: :code_review_workflow do
  let_it_be(:user) { build_stubbed(:user) }

  let(:host_class) do
    Class.new do
      include Gitlab::NotesCreateRateLimit

      attr_reader :current_user, :rate_limit_call

      def initialize(current_user)
        @current_user = current_user
      end

      def check_rate_limit!(key, **options, &block)
        @rate_limit_call = { key: key, options: options, block: block }
      end
    end
  end

  let(:host) { host_class.new(user) }

  describe '#check_notes_create_rate_limit!' do
    before do
      stub_application_setting(notes_create_limit: 7, notes_create_limit_allowlist: ['allowed_user'])
    end

    it 'checks the notes_create limit for the current user with the allowlist and no cost' do
      host.check_notes_create_rate_limit!

      expect(host.rate_limit_call).to include(
        key: :notes_create,
        options: { scope: { user: user }, users_allowlist: ['allowed_user'] }
      )
    end

    it 'charges a cost below the limit as it is' do
      host.check_notes_create_rate_limit!(cost: 3)

      expect(host.rate_limit_call[:options]).to include(cost: 3)
    end

    it 'caps a cost above the limit at the limit' do
      host.check_notes_create_rate_limit!(cost: 12)

      expect(host.rate_limit_call[:options]).to include(cost: 7)
    end

    it 'passes the block on to check_rate_limit!' do
      block = proc { :throttled }

      host.check_notes_create_rate_limit!(cost: 3, &block)

      expect(host.rate_limit_call[:block]).to eq(block)
    end
  end
end
