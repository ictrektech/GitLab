# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::DisconnectWatcher, feature_category: :knowledge_graph do
  let(:sockets) { UNIXSocket.pair }
  let(:socket) { sockets.first }
  let(:peer) { sockets.last }
  let(:cancelled) { Queue.new }
  let(:call) { instance_double(GRPC::Core::Call) }

  before do
    allow(call).to receive(:cancel) { cancelled << true }
  end

  after do
    sockets.each { |s| s.close unless s.closed? }
  end

  it 'cancels the call when the client closes the connection', :aggregate_failures do
    watch = described_class.watch(socket, call)

    peer.close

    expect(cancelled.pop(timeout: 2)).to be(true)
    expect(watch.cancelled).to be(true)
  end

  it 'does not cancel an unwatched socket' do
    described_class.unwatch(described_class.watch(socket, call))

    peer.close

    expect(cancelled.pop(timeout: 0.2)).to be_nil
  end

  it 'does not cancel when the socket has unread data' do
    watch = described_class.watch(socket, call)

    peer.write('x')

    expect(cancelled.pop(timeout: 0.2)).to be_nil
  ensure
    described_class.unwatch(watch)
  end

  it 'keeps watching after cancelling a call raises', :aggregate_failures do
    failing_call = instance_double(GRPC::Core::Call)
    allow(failing_call).to receive(:cancel).and_raise(StandardError, 'boom')
    tracked = Queue.new
    allow(Gitlab::ErrorTracking).to receive(:track_exception) { |error| tracked << error }
    other_socket, other_peer = UNIXSocket.pair

    described_class.watch(other_socket, failing_call)
    other_peer.close

    expect(tracked.pop(timeout: 2)).to have_attributes(message: 'boom')

    described_class.watch(socket, call)
    peer.close

    expect(cancelled.pop(timeout: 2)).to be(true)
  ensure
    [other_socket, other_peer].each { |s| s.close unless s.nil? || s.closed? }
  end

  it 'rebuilds the watcher when its thread died' do
    watcher = described_class.instance
    watcher.instance_variable_get(:@thread).kill.join

    expect(described_class.instance).not_to equal(watcher)
  end

  it 'rebuilds the watcher in a forked process' do
    watcher = described_class.instance
    pid = Process.pid
    allow(Process).to receive(:pid).and_return(pid + 1)

    expect(described_class.instance).not_to equal(watcher)
  end

  it 'keeps watching after a watched socket is closed locally' do
    other_socket, other_peer = UNIXSocket.pair
    described_class.watch(other_socket, call)
    other_socket.close

    described_class.watch(socket, call)
    peer.close

    expect(cancelled.pop(timeout: 2)).to be(true)
  ensure
    [other_socket, other_peer].each { |s| s.close unless s.nil? || s.closed? }
  end

  it 'leaves an idle watched socket alone', :aggregate_failures do
    watch = described_class.watch(socket, call)

    described_class.instance.send(:check, socket)

    expect(watch.cancelled).to be_nil
    expect(call).not_to have_received(:cancel)
  ensure
    described_class.unwatch(watch)
  end

  it 'ignores a closed socket that is not watched' do
    socket.close

    expect { described_class.instance.send(:check, socket) }.not_to raise_error
  end

  it 'ignores unwatch without a watch or a watcher' do
    watcher = described_class.instance
    described_class.instance_variable_set(:@instance, nil)

    expect do
      described_class.unwatch(nil)
      described_class.unwatch(described_class::Watch.new(socket, call))
    end.not_to raise_error
  ensure
    described_class.instance_variable_set(:@instance, watcher)
  end

  it 'ignores sockets that cannot be peeked' do
    expect(described_class.watch(nil, call)).to be_nil
  end
end
