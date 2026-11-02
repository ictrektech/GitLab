# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::ChatHistoryCache, :use_clean_rails_memory_store_caching,
  feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }

  def message(content, message_type = 'agent')
    { 'content' => content, 'message_type' => message_type }
  end

  def add_header(thread_ts, parent_ts)
    create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: thread_ts, parent_ts: parent_ts)
  end

  def add_blob(thread_ts, messages, version:, step_action: 'conversation')
    create(:duo_workflows_checkpoint_blob, workflow: workflow, thread_ts: thread_ts, channel: 'ui_chat_log',
      version: version, step_action: step_action, data: Zlib::Deflate.deflate(Gitlab::Json.dump(messages)))
  end

  def add_checkpoint(thread_ts, parent_ts, messages, version:)
    add_header(thread_ts, parent_ts)
    add_blob(thread_ts, messages, version: version)
  end

  # One request, on a fresh workflow so no memoized header rows carry over.
  def read(blobs_for: nil)
    reader = Ai::DuoWorkflows::Workflow.find(workflow.id)
    checkpoint = reader.latest_checkpoint_header
    cache = described_class.new([checkpoint])
    loaded_thread_ts = cache.thread_ts_to_load.sort
    blobs = Ai::DuoWorkflows::Workflow
      .history_blobs_for_workflows([reader], blobs_for || loaded_thread_ts, 'ui_chat_log')
      .fetch(reader.id, [])

    history = cache.history(checkpoint, blobs)
    cache.write

    { history: history, loaded_thread_ts: loaded_thread_ts }
  end

  def uncached_history
    reader = Ai::DuoWorkflows::Workflow.find(workflow.id)

    reader.channel_message_history(reader.latest_checkpoint_header, 'ui_chat_log')
  end

  before do
    add_checkpoint('ts-0', nil, [message('greeting')], version: '1')
    add_checkpoint('ts-1', 'ts-0', [message('hi', 'user')], version: '2')
    # A compaction step writes no delta: its new entries only exist in the snapshot.
    add_header('ts-2', 'ts-1')
    add_blob('ts-2', [message('greeting'), message('hi', 'user'), message('hello')],
      version: '3', step_action: 'compaction')
  end

  it 'folds the whole chain on a miss' do
    expect(read).to eq(history: uncached_history, loaded_thread_ts: %w[ts-0 ts-1 ts-2])
  end

  it 'loads no blob and writes nothing on a hit' do
    read

    expect(Rails.cache).not_to receive(:write_multi)
    expect(read).to eq(history: uncached_history, loaded_thread_ts: [])
  end

  it 'folds only the blobs of newer checkpoints onto the cached history' do
    read
    add_checkpoint('ts-3', 'ts-2', [message('more', 'user')], version: '4')

    expect(read).to eq(history: uncached_history, loaded_thread_ts: %w[ts-3])
  end

  it 'writes nothing when a pending blob was not loaded' do
    read(blobs_for: %w[ts-0 ts-1])

    expect(read).to eq(history: uncached_history, loaded_thread_ts: %w[ts-0 ts-1 ts-2])
  end

  it 'ignores loaded blobs that the cached history already holds', :aggregate_failures do
    read

    result = nil
    recorder = ActiveRecord::QueryRecorder.new { result = read(blobs_for: %w[ts-0 ts-1 ts-2]) }

    expect(result[:history]).to eq(uncached_history)
    # The chat log counts and the page's load, with no second load to rebuild.
    expect(recorder.log.grep(/p_duo_workflows_checkpoint_blobs/).size).to eq(2)
  end

  it 're-applies an alternative count that changed after the history was cached', :aggregate_failures do
    read
    # A retry of 'hi' on a branch the user then left, so the latest checkpoint stays on this one.
    add_checkpoint('ts-1b', 'ts-0', [message('hi again', 'user')], version: '2')

    result = read

    expect(result).to eq(history: uncached_history, loaded_thread_ts: [])
    expect(result[:history].find { |entry| entry['content'] == 'hi' }['alternative_count']).to eq(1)
  end

  it 'serves the cached history after a group start wrote a snapshot and its delta', :aggregate_failures do
    # The gateway writes the full log and the step's delta under one version.
    add_header('ts-3', 'ts-2')
    add_blob('ts-3', [message('greeting'), message('hi', 'user'), message('hello'), message('more', 'user')],
      version: '4', step_action: 'compaction')
    add_blob('ts-3', [message('more', 'user')], version: '4')

    expect(read[:history].pluck('content')).to eq(%w[greeting hi hello more])
    expect(read).to eq(history: uncached_history, loaded_thread_ts: [])
  end

  it 'rebuilds when a retry adds a blob to a cached checkpoint', :aggregate_failures do
    read
    # The conversation row wins its version over the compaction, so 'hello' changes in place.
    add_blob('ts-2', [message('hello again')], version: '3')

    result = read

    expect(result).to eq(history: uncached_history, loaded_thread_ts: %w[ts-0 ts-1 ts-2])
    expect(result[:history].pluck('content')).to eq(['greeting', 'hi', 'hello again'])
  end

  it 'rebuilds when a newer checkpoint has a blob that sorts before the cached ones', :aggregate_failures do
    read
    add_checkpoint('ts-3', 'ts-2', [message('more', 'user')], version: '4')
    # As if the blob took its id before the cached blobs did, and committed after them.
    lowest_id = Ai::DuoWorkflows::CheckpointBlob.where(workflow_id: workflow.id).minimum(:id)
    Ai::DuoWorkflows::CheckpointBlob.where(workflow_id: workflow.id, thread_ts: 'ts-3')
      .update_all(['id = ?', lowest_id - 1])

    result = read

    expect(result).to eq(history: uncached_history, loaded_thread_ts: %w[ts-3])
    expect(result[:history].pluck('content')).to eq(%w[more greeting hi hello])
  end

  it 'rebuilds when the latest checkpoint forks off the cached chain', :aggregate_failures do
    read
    add_checkpoint('ts-3', 'ts-1', [message('hello from a retry')], version: '3')

    result = read

    expect(result).to eq(history: uncached_history, loaded_thread_ts: %w[ts-0 ts-1 ts-3])
    expect(result[:history].pluck('content')).to eq(['greeting', 'hi', 'hello from a retry'])
  end

  describe '#covers?' do
    it 'covers only the newest of the checkpoints passed for one workflow' do
      older = Ai::DuoWorkflows::CheckpointHeader.find_by(workflow_id: workflow.id, thread_ts: 'ts-1')
      newer = Ai::DuoWorkflows::CheckpointHeader.find_by(workflow_id: workflow.id, thread_ts: 'ts-2')
      cache = described_class.new([newer, older])

      expect([older, newer].map { |checkpoint| cache.covers?(checkpoint) }).to eq([false, true])
    end
  end
end
