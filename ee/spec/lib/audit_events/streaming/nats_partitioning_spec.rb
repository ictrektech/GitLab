# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::NatsPartitioning, feature_category: :audit_events do
  def stub_partition_counts(publish: nil, drain: nil)
    stub_config(nats: { publish_partition_count: publish, drain_partition_count: drain })
  end

  # A wide default range so the mapping/routing examples can use partition
  # indices like 200; the count-specific describe blocks override this.
  before do
    stub_partition_counts(publish: 256, drain: 256)
  end

  describe '.publish_partition_for' do
    it 'picks a random partition within range' do
      expect(described_class).to receive(:rand)
        .with(described_class.publish_partition_count).and_return(7)

      expect(described_class.publish_partition_for(42)).to eq(7)
    end

    it 'keeps the partition within range for any group id', :aggregate_failures do
      [1, 42, 255, 256, 257, 1_000_000, 999_999_999].each do |group_id|
        partition = described_class.publish_partition_for(group_id)

        expect(partition).to be_between(0, described_class.publish_partition_count - 1)
      end
    end

    it 'derives the partition from the random source, not the group id' do
      allow(described_class).to receive(:rand).and_return(3, 9)

      # Same group id can land on different partitions across calls.
      expect(described_class.publish_partition_for(42)).to eq(3)
      expect(described_class.publish_partition_for(42)).to eq(9)
    end

    it 'routes only a true nil (instance-scoped) to no numeric partition' do
      expect(described_class.publish_partition_for(nil)).to be_nil
    end

    it 'raises on a non-numeric id rather than silently misrouting', :aggregate_failures do
      expect { described_class.publish_partition_for('') }.to raise_error(ArgumentError)
      expect { described_class.publish_partition_for('not-a-number') }.to raise_error(ArgumentError)
      expect { described_class.publish_partition_for('42x') }.to raise_error(ArgumentError)
      expect { described_class.publish_partition_for([42]) }.to raise_error(TypeError)
    end
  end

  describe '.subject_for' do
    it 'builds the subject for the randomly chosen partition' do
      allow(described_class).to receive(:rand).and_return(42)

      expect(described_class.subject_for(123)).to eq('audit_events.streaming.42')
    end

    it 'can route the same group id to different partition subjects' do
      allow(described_class).to receive(:rand).and_return(1, 200)

      expect(described_class.subject_for(42)).to eq('audit_events.streaming.1')
      expect(described_class.subject_for(42)).to eq('audit_events.streaming.200')
    end

    it 'routes instance-scoped events to the dedicated instance subject' do
      expect(described_class.subject_for(nil)).to eq(described_class::INSTANCE_SUBJECT)
    end

    it 'raises on a malformed group id' do
      expect { described_class.subject_for('not-a-number') }.to raise_error(ArgumentError)
    end

    it 'isolates the instance subject from every numeric partition subject' do
      numeric_subjects = (0...described_class.drain_partition_count)
        .map { |p| described_class.subject_for_partition(p) }

      expect(numeric_subjects).not_to include(described_class::INSTANCE_SUBJECT)
    end
  end

  describe '.drain_partition_count' do
    it 'defaults to DEFAULT_PARTITION_COUNT when unset' do
      stub_partition_counts(drain: nil)

      expect(described_class.drain_partition_count).to eq(described_class::DEFAULT_PARTITION_COUNT)
    end

    it 'returns the configured value' do
      stub_partition_counts(drain: 4)

      expect(described_class.drain_partition_count).to eq(4)
    end

    it 'floors a zero or negative value at 1', :aggregate_failures do
      stub_partition_counts(drain: 0)
      expect(described_class.drain_partition_count).to eq(1)

      stub_partition_counts(drain: -5)
      expect(described_class.drain_partition_count).to eq(1)
    end
  end

  describe '.publish_partition_count' do
    it 'defaults to DEFAULT_PARTITION_COUNT when unset' do
      stub_partition_counts(publish: nil, drain: nil)

      expect(described_class.publish_partition_count).to eq(described_class::DEFAULT_PARTITION_COUNT)
    end

    it 'returns the configured value when within the drain count' do
      stub_partition_counts(publish: 4, drain: 8)

      expect(described_class.publish_partition_count).to eq(4)
    end

    it 'caps at the drain count so publishing never targets an undrained partition' do
      stub_partition_counts(publish: 16, drain: 8)

      expect(described_class.publish_partition_count).to eq(8)
    end

    it 'floors a zero or negative value at 1' do
      stub_partition_counts(publish: 0, drain: 8)

      expect(described_class.publish_partition_count).to eq(1)
    end
  end

  describe '.partition_keys' do
    it 'lists every numeric partition plus the instance lane', :aggregate_failures do
      keys = described_class.partition_keys

      expect(keys.size).to eq(described_class.drain_partition_count + 1)
      expect(keys.first).to eq(0)
      expect(keys).to include(described_class.drain_partition_count - 1)
      expect(keys.last).to eq(described_class::INSTANCE_KEY)
    end

    it 'tracks the configured drain count', :aggregate_failures do
      stub_partition_counts(drain: 3)

      keys = described_class.partition_keys

      expect(keys).to eq([0, 1, 2, described_class::INSTANCE_KEY])
    end
  end

  describe '.subject_for_key' do
    it 'maps a numeric key to the partition subject' do
      expect(described_class.subject_for_key(7)).to eq('audit_events.streaming.7')
    end

    it 'maps a stringified numeric key the same as its integer (survives arg round-trips)' do
      expect(described_class.subject_for_key('7')).to eq(described_class.subject_for_key(7))
    end

    it 'maps the instance key to the instance subject' do
      expect(described_class.subject_for_key(described_class::INSTANCE_KEY))
        .to eq(described_class::INSTANCE_SUBJECT)
    end

    it 'raises ArgumentError (not TypeError) for an out-of-range or nil key', :aggregate_failures do
      expect { described_class.subject_for_key(described_class.drain_partition_count) }.to raise_error(ArgumentError)
      expect { described_class.subject_for_key(nil) }.to raise_error(ArgumentError)
    end
  end

  describe '.durable_for_key' do
    it 'maps a numeric key to the partition durable' do
      expect(described_class.durable_for_key(7)).to eq('audit_streaming_consumer_7')
    end

    it 'maps a stringified numeric key the same as its integer (survives arg round-trips)' do
      expect(described_class.durable_for_key('7')).to eq(described_class.durable_for_key(7))
    end

    it 'maps the instance key to the instance durable' do
      expect(described_class.durable_for_key(described_class::INSTANCE_KEY))
        .to eq(described_class::INSTANCE_DURABLE)
    end
  end

  describe '.subject_for_partition' do
    it 'builds the subject for a partition index' do
      expect(described_class.subject_for_partition(7)).to eq('audit_events.streaming.7')
    end

    it 'raises for an out-of-range partition', :aggregate_failures do
      expect { described_class.subject_for_partition(-1) }.to raise_error(ArgumentError)
      expect { described_class.subject_for_partition(described_class.drain_partition_count) }
        .to raise_error(ArgumentError)
    end
  end

  describe '.durable_for_partition' do
    it 'builds a per-partition durable name' do
      expect(described_class.durable_for_partition(7)).to eq('audit_streaming_consumer_7')
    end

    it 'raises for an out-of-range partition' do
      expect { described_class.durable_for_partition(described_class.drain_partition_count) }
        .to raise_error(ArgumentError)
    end
  end
end
