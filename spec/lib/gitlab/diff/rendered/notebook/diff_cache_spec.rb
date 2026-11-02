# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::Rendered::Notebook::DiffCache, :use_clean_rails_redis_caching, feature_category: :mlops do
  let_it_be(:project) { create(:project) }

  let(:old_blob) { instance_double(Gitlab::Git::Blob, id: 'old-blob-id') }
  let(:new_blob) { instance_double(Gitlab::Git::Blob, id: 'new-blob-id') }
  let(:cache) { described_class.new(project: project, old_blob: old_blob, new_blob: new_blob) }
  let(:notebook_diff) do
    IpynbDiff.diff(notebook("print('é')"), notebook("print('ü')"), diffy_opts: { include_diff_info: true })
  end

  def notebook(source)
    Gitlab::Json.generate(
      cells: [{ cell_type: 'code', execution_count: 1, metadata: {}, outputs: [], source: [source] }],
      metadata: {}, nbformat: 4, nbformat_minor: 5
    )
  end

  def output(diff)
    [diff.to_s(:text), diff.from.as_text, diff.to.as_text, diff.from.blocks.pluck(:source_line),
      diff.to.blocks.pluck(:source_line)]
  end

  def fetch_again
    yielded = false
    result = described_class.new(project: project, old_blob: old_blob, new_blob: new_blob).fetch do
      yielded = true
      notebook_diff
    end

    [result, yielded]
  end

  def ttl
    Gitlab::Redis::Cache.with { |redis| redis.ttl("#{Gitlab::Redis::Cache::CACHE_NAMESPACE}:#{cache.key}") }
  end

  # When this fails, change VERSION so that entries of the old output are not read, then update the fingerprint.
  describe 'VERSION' do
    let(:options) { Gitlab::Diff::Rendered::Notebook::DiffFile::IPYNB_DIFF_OPTIONS }
    let(:expected_fingerprint) { 'c9ac3097a6b93aca4a1a041bb55c17ba42a5b52183965fcb00d16e295fbf0e62' }

    it 'matches the fingerprint of the rendered notebooks' do
      from, to = %w[from to].map { |name| File.read(Rails.root.join("gems/ipynbdiff/spec/testdata/#{name}.ipynb")) }
      notebook_diff = IpynbDiff.diff(from, to, **options)
      rendered = [notebook_diff.from, notebook_diff.to].map { |nb| [nb.as_text, nb.blocks.pluck(:source_line)] }
      fingerprint = OpenSSL::Digest::SHA256.hexdigest(Gitlab::Json.generate([options, rendered]))

      expect(described_class::VERSION => fingerprint).to eq(1 => expected_fingerprint)
    end
  end

  describe '#key' do
    it 'contains the version, the project and both blob ids' do
      expect(cache.key).to eq("notebook_diff:#{described_class::VERSION}:#{project.id}:old-blob-id:new-blob-id")
    end

    context 'when the notebook is new' do
      let(:old_blob) { nil }

      it 'leaves the old blob id empty' do
        expect(cache.key).to eq("notebook_diff:#{described_class::VERSION}:#{project.id}::new-blob-id")
      end
    end
  end

  describe '#fetch' do
    before do
      allow(Gitlab::AppLogger).to receive(:info).and_call_original
    end

    it 'returns the rendered diff and caches it' do
      expect(output(cache.fetch { notebook_diff })).to eq(output(notebook_diff))

      cached, yielded = fetch_again

      expect(yielded).to be(false)
      expect(Gitlab::AppLogger).to have_received(:info).with(message: 'IPYNB_DIFF_CACHE_HIT').once
      expect(output(cached)).to eq(output(notebook_diff))
      expect(output(cached).first(3).map(&:encoding)).to eq(output(notebook_diff).first(3).map(&:encoding))
    end

    it 'rebuilds the notebook texts from the text diff instead of storing them' do
      cache.fetch { notebook_diff }

      expect(Rails.cache.read(cache.key).values_at(:from, :to).pluck(:as_text)).to eq([nil, nil])
    end

    context 'when the text diff does not hold both notebooks' do
      let(:notebook_diff) do
        IpynbDiff.diff(notebook("print('é')"), notebook("print('é')"), diffy_opts: { include_diff_info: true })
      end

      it 'stores the notebook texts' do
        cache.fetch { notebook_diff }

        cached, = fetch_again

        expect(notebook_diff.to_s(:text)).to be_empty
        expect(Rails.cache.read(cache.key).values_at(:from, :to).pluck(:as_text)).to all(be_present)
        expect(output(cached)).to eq(output(notebook_diff))
      end
    end

    it 'expires the entry after EXPIRATION' do
      cache.fetch { notebook_diff }

      expect(ttl).to be_within(10).of(described_class::EXPIRATION.to_i)
    end

    it 'does not share entries between projects' do
      cache.fetch { notebook_diff }

      other_cache = described_class.new(project: create(:project), old_blob: old_blob, new_blob: new_blob)

      expect { |block| other_cache.fetch(&block) }.to yield_control
    end

    context 'when the entry is larger than MAX_BYTES' do
      # The text diff fits, but the source lines and the serialization overhead do not.
      before do
        stub_const("#{described_class}::MAX_BYTES", notebook_diff.to_s(:text).bytesize + 10)
      end

      it 'returns the rendered diff, and later fetches return nil without rendering' do
        expect(cache.fetch { notebook_diff }).to be(notebook_diff)
        expect(Gitlab::AppLogger).to have_received(:info).with(message: 'IPYNB_DIFF_TOO_LARGE').once

        cached, yielded = fetch_again

        expect(cached).to be_nil
        expect(yielded).to be(false)
        expect(ttl).to be_within(10).of(described_class::EXPIRATION.to_i)
        expect(Gitlab::AppLogger).to have_received(:info)
          .with(message: 'IPYNB_DIFF_CACHE_SKIPPED', skip_reason: :too_large).once
      end
    end

    context 'when the render times out' do
      it 'raises, and later fetches return nil without rendering' do
        expect { cache.fetch { raise Timeout::Error } }.to raise_error(Timeout::Error)

        cached, yielded = fetch_again

        expect(cached).to be_nil
        expect(yielded).to be(false)
        expect(ttl).to be_within(10).of(described_class::TIMEOUT_EXPIRATION.to_i)
        expect(Gitlab::AppLogger).to have_received(:info)
          .with(message: 'IPYNB_DIFF_CACHE_SKIPPED', skip_reason: :foreground_timeout).once
      end

      it 'renders again in Sidekiq, and caches the diff' do
        expect { cache.fetch { raise Timeout::Error } }.to raise_error(Timeout::Error)

        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
        cached, yielded = fetch_again

        expect(yielded).to be(true)
        expect(output(cached)).to eq(output(notebook_diff))
        expect(ttl).to be_within(10).of(described_class::EXPIRATION.to_i)
      end
    end

    context 'when the render times out in Sidekiq' do
      before do
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
      end

      it 'raises, and later fetches in Sidekiq and on the web return nil without rendering' do
        expect { cache.fetch { raise Timeout::Error } }.to raise_error(Timeout::Error)

        cached_in_sidekiq, yielded_in_sidekiq = fetch_again
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(false)
        cached_on_web, yielded_on_web = fetch_again

        expect([cached_in_sidekiq, cached_on_web]).to all(be_nil)
        expect([yielded_in_sidekiq, yielded_on_web]).to all(be(false))
      end
    end

    describe 'the returned diff' do
      subject(:cached_diff) { cache.fetch { notebook_diff } }

      it 'returns the text diff for the text format and by default' do
        expect(cached_diff.to_s(:text)).to eq(notebook_diff.to_s(:text))
        expect(cached_diff.to_s).to eq(notebook_diff.to_s)
      end

      it 'raises for other formats' do
        expect { cached_diff.to_s(:html) }.to raise_error(ArgumentError, 'Unsupported format: html')
      end
    end

    context 'when the block returns nil' do
      it 'returns nil without caching' do
        expect(cache.fetch { nil }).to be_nil

        _, yielded = fetch_again

        expect(yielded).to be(true)
      end
    end
  end
end
