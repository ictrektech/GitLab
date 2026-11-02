# frozen_string_literal: true

FactoryBot.define do
  factory :ai_conversation_thread, class: '::Ai::Conversation::Thread' do
    conversation_type { :duo_chat }
    last_updated_at { Time.zone.now }
    organization { association(:common_organization) }
    user

    trait :expired do
      last_updated_at { 31.days.ago }
    end

    trait :with_messages do
      messages { Array.new(2) { association(:ai_conversation_message, strategy: :build, thread: instance) } }
    end
  end
end
