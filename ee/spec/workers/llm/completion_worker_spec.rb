# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Llm::CompletionWorker, feature_category: :ai_abstraction_layer do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:resource) { create(:issue, project: project) }
  let_it_be(:thread) { create(:ai_conversation_thread, user: user) }

  let(:user_agent) { 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' }
  let(:options) { { 'key' => 'value' } }
  let(:ai_action_name) { :summarize_comments }

  let(:prompt_message) do
    build(:ai_message,
      user: user, resource: resource, ai_action: ai_action_name, request_id: 'uuid', user_agent: user_agent,
      thread: thread
    )
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  describe '#perform' do
    subject { worker.perform(described_class.serialize_message(prompt_message), options) }

    let(:worker) { described_class.new }
    let(:session) { ActionController::TestSession.new }

    def expect_completion_service_call
      expect_next_instance_of(
        Llm::Internal::CompletionService,
        an_object_having_attributes(
          user: user,
          resource: resource,
          request_id: 'uuid',
          ai_action: ai_action_name.to_s,
          thread: thread
        ),
        options
      ) do |instance|
        expect(instance).to receive(:execute)
      end
    end

    it 'calls Llm::Internal::CompletionService and tracks event' do
      expect_completion_service_call
      expect(worker).to receive(:log_extra_metadata_on_done).with(:ai_action, ai_action_name.to_s)

      subject

      expect_snowplow_event(
        category: described_class.to_s,
        action: 'perform_completion_worker',
        label: ai_action_name.to_s,
        property: 'uuid',
        user: user,
        client: 'web'
      )
    end

    it 'tracks user AI feature utilization' do
      expect_completion_service_call
      expect(worker).to receive(:log_extra_metadata_on_done).with(:ai_action, ai_action_name.to_s)
      expect(Gitlab::Tracking::AiTracking).to receive(:track_user_activity).with(user)

      subject
    end

    context 'when warden.user.user.key is nil' do
      it 'simulates it' do
        expect_completion_service_call
        expect(worker).to receive(:log_extra_metadata_on_done).with(:ai_action, ai_action_name.to_s)

        Gitlab::Session.with_session(session) do
          subject

          expect(Gitlab::Session.current['warden.user.user.key']).to match_array([[user.id], instance_of(String)])
        end
      end

      context 'when sessionless' do
        it 'does nothing' do
          expect_completion_service_call
          expect(worker).to receive(:log_extra_metadata_on_done).with(:ai_action, ai_action_name.to_s)

          subject

          expect(Gitlab::Session.current).to be_nil
        end
      end
    end

    context 'when the thread no longer exists' do
      subject do
        worker.perform(
          described_class.serialize_message(prompt_message).merge('thread_id' => non_existing_record_id),
          options
        )
      end

      it 'returns early without calling the completion service' do
        expect(Llm::Internal::CompletionService).not_to receive(:new)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped, 'user_or_thread_not_found')

        expect { subject }.not_to raise_error
      end
    end

    context 'when the user no longer exists' do
      subject do
        worker.perform(
          described_class.serialize_message(prompt_message)
                         .merge('user' => "gid://gitlab/User/#{non_existing_record_id}"),
          options
        )
      end

      it 'returns early without calling the completion service' do
        expect(Llm::Internal::CompletionService).not_to receive(:new)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped, 'user_or_thread_not_found')

        expect { subject }.not_to raise_error
      end
    end

    context 'when deserializing the message raises' do
      subject do
        worker.perform(described_class.serialize_message(prompt_message).merge('user' => 'not-a-gid'), options)
      end

      it 'raises without logging a skip reason' do
        expect(worker).not_to receive(:log_extra_metadata_on_done).with(:skipped, anything)

        expect { subject }.to raise_error(Gitlab::Graphql::Errors::ArgumentError)
      end
    end
  end

  describe '.serialize_message' do
    it 'returns a JSON-compatbile hash' do
      serialized_message = described_class.serialize_message(prompt_message)

      expect(serialized_message).to be_a(Hash)
      expect(serialized_message['user']).to eq(user.to_gid.to_s)
      expect(serialized_message['context']['resource']).to eq(resource.to_gid.to_s)
      expect(serialized_message['context']['project']).to eq(project.to_gid.to_s)
      expect(serialized_message['thread_id']).to eq(thread.id)
      expect(serialized_message['ai_action']).to eq(ai_action_name.to_s)
    end

    it 'can serialize and deserialize message' do
      serialized_message = described_class.serialize_message(prompt_message)
      deserialized_message = described_class.send(:deserialize_message, serialized_message, options)

      expect(deserialized_message).to be_a(Gitlab::Llm::AiMessage)
      expect(deserialized_message.user).to eq(prompt_message.user)
      expect(deserialized_message.resource).to eq(prompt_message.resource)
      expect(deserialized_message.thread).to eq(prompt_message.thread)
      expect(deserialized_message.ai_action).to eq(prompt_message.ai_action.to_s)
    end
  end

  describe '.deserialize_message' do
    context 'when the thread no longer exists' do
      it 'returns nil' do
        serialized_message = described_class.serialize_message(prompt_message)
                                            .merge('thread_id' => non_existing_record_id)

        expect(described_class.deserialize_message(serialized_message, options)).to be_nil
      end
    end

    context 'when the user no longer exists' do
      it 'returns nil' do
        serialized_message = described_class.serialize_message(prompt_message)
                                            .merge('user' => "gid://gitlab/User/#{non_existing_record_id}")

        expect(described_class.deserialize_message(serialized_message, options)).to be_nil
      end
    end
  end

  describe '.perform_for' do
    let(:ip_address) { '1.1.1.1' }

    before do
      allow(::Gitlab::IpAddressState).to receive(:current).and_return(ip_address)
    end

    it 'sets set_ip_address to true' do
      described_class.perform_for(prompt_message, options)

      job = described_class.jobs.first

      expect(job).to include(
        'ip_address_state' => ip_address,
        'args' => [
          hash_including("ai_action" => ai_action_name.to_s),
          options.as_json
        ]
      )
    end

    it 'sets set_session_id' do
      allow(::Gitlab::Session).to receive(:session_id_for_worker).and_return('abc')

      described_class.perform_for(prompt_message, options)

      job = described_class.jobs.first

      expect(job).to include(
        'ip_address_state' => ip_address,
        'set_session_id' => 'abc',
        'args' => [
          hash_including("ai_action" => ai_action_name.to_s),
          options.as_json
        ]
      )
    end
  end

  describe '.resource' do
    subject { described_class.resource(message_hash) }

    let(:message_hash) do
      {
        'context' => {
          'resource' => resource.to_gid.to_s
        }
      }
    end

    it 'returns the resource' do
      expect(subject).to eq(resource)
    end

    context 'when the resource no longer exists' do
      let(:message_hash) { { 'context' => { 'resource' => "gid://gitlab/Issue/#{non_existing_record_id}" } } }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when the resource is a commit' do
      let_it_be(:project) { create(:project, :public, :repository) }
      let_it_be(:commit)  { project.commit }

      let(:message_hash) do
        {
          'context' => {
            'resource' => commit.to_gid.to_s,
            'project' => project.to_gid.to_s
          }
        }
      end

      it 'returns the project commit' do
        expect(subject).to eq(commit)
      end

      context 'when the commit no longer exists' do
        let(:message_hash) do
          { 'context' => { 'resource' => "gid://gitlab/Commit/#{'a' * 40}", 'project' => project.to_gid.to_s } }
        end

        it 'returns nil' do
          is_expected.to be_nil
        end
      end

      context 'when the project no longer exists' do
        let(:message_hash) do
          {
            'context' => {
              'resource' => commit.to_gid.to_s,
              'project' => "gid://gitlab/Project/#{non_existing_record_id}"
            }
          }
        end

        it 'returns nil' do
          is_expected.to be_nil
        end
      end
    end
  end
end
