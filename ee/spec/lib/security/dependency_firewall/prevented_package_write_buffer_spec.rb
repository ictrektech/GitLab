# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedPackageWriteBuffer, :clean_gitlab_redis_shared_state,
  feature_category: :dependency_firewall do
  let(:buffer) { described_class.new(buffer_key: 'test_prevented_packages') }
  let(:now) { Time.current.utc.change(usec: 0) }

  def entry(
    project_id: 42, rule_type: 0, identifier: 'pkg:npm/a@1', seen_at: now, blocked: true,
    warned: false, severity: nil)
    {
      project_id: project_id,
      rule_type: rule_type,
      identifier: identifier,
      seen_at: seen_at,
      blocked: blocked,
      warned: warned,
      severity: severity
    }
  end

  def staged(limit = 10)
    buffer.staged_batch(limit).first
  end

  def drain(limit = 10)
    buffer.stage!
    staged(limit)
  end

  describe 'key persistence' do
    def ttl_of(key)
      Gitlab::Redis::SharedState.with { |r| r.ttl(key) }
    end

    # -1 is Redis for "key exists with no expiry"
    it 'sets no TTL on the live key, since expiring buffered entries would lose them' do
      buffer.add(entry)

      expect(ttl_of(buffer.send(:buffer_key))).to eq(-1)
    end

    it 'sets no TTL on the staged key, so entries survive an arbitrarily long flush outage' do
      buffer.add(entry)
      buffer.stage!

      expect(ttl_of(buffer.send(:staged_key))).to eq(-1)
    end

    it 'leaves no key behind once the staged entries are removed' do
      buffer.add(entry)
      buffer.stage!
      buffer.remove_staged(staged)

      # -2 is Redis for "key does not exist"
      expect(ttl_of(buffer.send(:staged_key))).to eq(-2)
    end
  end

  describe 'Redis Cluster key placement' do
    it 'gives the live and staged keys the same hash tag so they share a slot', :aggregate_failures do
      tag = ->(key) { key[/\{(.+?)\}/, 1] }

      live = buffer.send(:buffer_key)
      staged = buffer.send(:staged_key)

      expect(tag.call(live)).to be_present
      expect(tag.call(staged)).to eq(tag.call(live))
    end
  end

  describe '#add' do
    it 'round-trips one entry with every attribute' do
      buffer.add(entry(severity: 6, warned: true))

      expect(drain).to contain_exactly(
        have_attributes(
          project_id: 42,
          rule_type: 0,
          identifier: 'pkg:npm/a@1',
          first_seen_at: be_like_time(now),
          last_blocked_at: be_like_time(now),
          last_warned_at: be_like_time(now),
          severity: 6
        )
      )
    end

    it 'merges repeat activity for the same key: min first_seen, max blocked', :aggregate_failures do
      buffer.add(entry(seen_at: now - 2.hours))
      buffer.add(entry(seen_at: now))

      entries = drain
      expect(entries.size).to eq(1)
      expect(entries.first).to have_attributes(
        first_seen_at: be_like_time(now - 2.hours),
        last_blocked_at: be_like_time(now)
      )
    end

    it 'keeps the max severity across merges' do
      buffer.add(entry(severity: 7))
      buffer.add(entry(severity: 4))

      expect(drain.first.severity).to eq(7)
    end

    it 'does not lose a warn timestamp when a later add only blocks', :aggregate_failures do
      buffer.add(entry(blocked: false, warned: true, seen_at: now - 1.hour))
      buffer.add(entry(blocked: true, warned: false, seen_at: now))

      merged = drain.first
      expect(merged.last_warned_at).to be_like_time(now - 1.hour)
      expect(merged.last_blocked_at).to be_like_time(now)
    end

    it 'returns nil timestamps and severity for what was never recorded' do
      buffer.add(entry(blocked: true, warned: false, severity: nil))

      expect(drain.first).to have_attributes(last_warned_at: nil, severity: nil)
    end

    it 'returns a nil block timestamp for a warn-only entry' do
      buffer.add(entry(blocked: false, warned: true))

      expect(drain.first).to have_attributes(last_blocked_at: nil, last_warned_at: be_like_time(now))
    end

    it 'rejects an array, since each call buffers one entry' do
      expect { buffer.add([entry]) }.to raise_error(ArgumentError, 'expects a single entry hash')
    end

    context 'with enum values that are not integers' do
      using RSpec::Parameterized::TableSyntax

      where(:attributes) do
        [
          [{ rule_type: 'risk_severity' }],
          [{ severity: 'high' }]
        ]
      end

      with_them do
        it 'raises instead of buffering an entry that would read back as another value', :aggregate_failures do
          expect { buffer.add(entry.merge(attributes)) }.to raise_error(ArgumentError)
          expect(buffer.live_size).to eq(0)
        end
      end
    end

    it 'keeps separate entries per rule type' do
      buffer.add(entry(rule_type: 0))
      buffer.add(entry(rule_type: 2))

      expect(drain.map(&:rule_type)).to contain_exactly(0, 2)
    end

    it 'keeps separate entries per identifier' do
      buffer.add(entry(identifier: 'pkg:npm/a@1'))
      buffer.add(entry(identifier: 'pkg:npm/a@2'))

      expect(drain.map(&:identifier)).to contain_exactly('pkg:npm/a@1', 'pkg:npm/a@2')
    end

    it 'preserves an identifier containing the separator character' do
      purl = 'pkg:golang/github.com/foo/bar@v1.0.0'
      buffer.add(entry(identifier: purl))

      expect(drain.first.identifier).to eq(purl)
    end

    it 'fails loudly on a missing key instead of silently mis-bucketing' do
      expect { buffer.add(rule_type: 0, identifier: 'pkg:npm/a@1', seen_at: now) }
        .to raise_error(KeyError)
    end
  end

  describe '#live_size' do
    it 'counts the live entries, which is the backlog signal the flush log reports' do
      buffer.add(entry(identifier: 'pkg:npm/a@1'))
      buffer.add(entry(identifier: 'pkg:npm/a@1'))
      buffer.add(entry(identifier: 'pkg:npm/b@1'))

      expect(buffer.live_size).to eq(2)
    end

    it 'falls to zero once the entries are staged' do
      buffer.add(entry)
      buffer.stage!

      expect(buffer.live_size).to eq(0)
    end
  end

  describe '#stage!' do
    it 'clears the live buffer so concurrent activity starts a fresh entry' do
      buffer.add(entry(seen_at: now - 1.hour))
      buffer.stage!
      buffer.add(entry(seen_at: now))

      expect(staged).to contain_exactly(
        have_attributes(last_blocked_at: be_like_time(now - 1.hour))
      )
    end

    it 'max-merges into entries left staged by an earlier failed flush instead of overwriting them' do
      buffer.add(entry(seen_at: now - 2.hours))
      buffer.stage!

      buffer.add(entry(seen_at: now))
      buffer.stage!

      expect(staged).to contain_exactly(
        have_attributes(
          first_seen_at: be_like_time(now - 2.hours),
          last_blocked_at: be_like_time(now)
        )
      )
    end

    it 'is a no-op when nothing has been buffered', :aggregate_failures do
      expect { buffer.stage! }.not_to raise_error
      expect(staged).to eq([])
    end
  end

  describe '#pop' do
    it 'is not supported, since this buffer is hash-shaped rather than a list' do
      expect { buffer.pop(10) }.to raise_error(NotImplementedError)
    end
  end

  describe '#staged_batch' do
    it 'returns an empty array when nothing is staged' do
      expect(staged).to eq([])
    end

    it 'does not remove what it returns, so entries survive a crash before the write commits',
      :aggregate_failures do
      buffer.add(entry)
      buffer.stage!

      expect(staged.size).to eq(1)
      expect(staged.size).to eq(1)
    end

    it 'returns the cursor to resume from, and "0" once the scan is complete' do
      buffer.add(entry)
      buffer.stage!

      expect(buffer.staged_batch(10)).to match_array([contain_exactly(have_attributes(identifier: 'pkg:npm/a@1')), '0'])
    end

    it 'returns every entry of a large backlog when resumed with the cursor' do
      # Enough to exceed hash-max-listpack-entries (128 by default, 512 in GDK), where HSCAN pages.
      1_000.times { |i| buffer.add(entry(identifier: "pkg:npm/a@#{i}")) }
      buffer.stage!

      entries = []
      cursor = '0'
      loop do
        page, cursor = buffer.staged_batch(100, cursor)
        entries.concat(page)
        break if cursor == '0'
      end

      expect(entries.map(&:identifier).uniq).to match_array(Array.new(1_000) { |i| "pkg:npm/a@#{i}" })
    end

    it 'returns entries whose to_row matches the upsert column set' do
      buffer.add(entry)

      expect(drain.first.to_row.keys).to contain_exactly(
        :project_id, :rule_type, :identifier, :first_seen_at, :last_blocked_at, :last_warned_at, :severity
      )
    end
  end

  describe '#remove_staged' do
    it 'clears only the entries it is given' do
      buffer.add(entry(identifier: 'pkg:npm/a@1'))
      buffer.add(entry(identifier: 'pkg:npm/b@1'))
      buffer.stage!

      rows = staged
      buffer.remove_staged(rows.select { |row| row.identifier == 'pkg:npm/a@1' })

      expect(staged).to contain_exactly(have_attributes(identifier: 'pkg:npm/b@1'))
    end

    it 'leaves the staged hash empty once everything is removed' do
      buffer.add(entry)
      buffer.stage!

      buffer.remove_staged(staged)

      expect(staged).to eq([])
    end

    it 'keeps an entry re-staged by a concurrent flush instead of discarding the merge' do
      buffer.add(entry(seen_at: now - 1.hour))
      buffer.stage!
      rows = staged

      # A lapsed lease lets the next run merge newer activity into the same field before this run
      # clears it. The merged value differs from what was read, so it must survive.
      buffer.add(entry(seen_at: now))
      buffer.stage!

      buffer.remove_staged(rows)

      expect(staged).to contain_exactly(
        have_attributes(last_blocked_at: be_like_time(now))
      )
    end

    it 'does nothing when given no entries' do
      expect { buffer.remove_staged([]) }.not_to raise_error
    end
  end
end
