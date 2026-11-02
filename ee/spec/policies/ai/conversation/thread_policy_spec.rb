# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Conversation::ThreadPolicy, feature_category: :chat_engine do
  subject(:policy) { described_class.new(current_user, thread) }

  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:thread) { create(:ai_conversation_thread, user: user) }
  let(:current_user) { user }

  describe 'delete_conversation_thread' do
    context 'when user owns the thread' do
      it { expect_allowed(:delete_conversation_thread) }
    end

    context 'when user does not own the thread' do
      let(:current_user) { other_user }

      it { expect_disallowed(:delete_conversation_thread) }
    end

    context 'when user is nil' do
      let(:current_user) { nil }

      it { expect_disallowed(:delete_conversation_thread) }
    end
  end
end
