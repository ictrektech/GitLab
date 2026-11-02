# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gitlab::Git::CommitStats, feature_category: :source_code_management do
  # `freeze: false` is required in this spec: one or more `let_it_be` subjects
  # cannot be frozen by default (deep_freeze traversal failure, a non-AR
  # subject, or an in-memory mutation that survives reload/refind). Do not
  # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
  # (see gitlab-org/gitlab#602925).
  let_it_be(:project, freeze: false) { create(:project, :repository) }

  let(:repository) { project.repository.raw }
  let(:commit) { Gitlab::Git::Commit.find(repository, TestEnv::BRANCH_SHA['feature']) }

  def verify_stats!
    stats = described_class.new(repository, commit)

    expect(stats).to have_attributes(
      additions: eq(5),
      deletions: eq(0),
      files: eq(1),
      total: eq(5)
    )
  end

  it 'returns commit stats and caches them', :use_clean_rails_redis_caching do
    expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id).and_call_original

    verify_stats!

    expect(Rails.cache.fetch("commit_stats:#{repository.gl_project_path}:#{commit.id}")).to eq([5, 0, 1])

    expect(repository.gitaly_commit_client).not_to receive(:commit_stats)

    verify_stats!
  end

  it 'handles old cache format gracefully', :use_clean_rails_redis_caching do
    old_cache_key = "commit_stats:#{repository.gl_project_path}:#{commit.id}"
    Rails.cache.write(old_cache_key, [5, 0])

    expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id).and_call_original

    stats = described_class.new(repository, commit)

    expect(stats).to have_attributes(
      additions: eq(5),
      deletions: eq(0),
      files: eq(1),
      total: eq(5)
    )
    expect(Rails.cache.fetch(old_cache_key)).to eq([5, 0, 1])
  end

  describe '.new', :use_clean_rails_redis_caching do
    let(:cache_key) { "commit_stats:#{repository.gl_project_path}:#{commit.id}" }
    let(:timed_out_cache_key) { "#{cache_key}:timed_out" }

    def build_stats
      described_class.new(repository, commit)
    end

    context 'when the repository container is a project wiki' do
      it 'returns stats from Gitaly', :aggregate_failures do
        allow(repository).to receive(:container).and_return(project.wiki)
        expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id).once.and_call_original

        expect(build_stats).to have_attributes(additions: 5, deletions: 0, files: 1, total: 5)
      end
    end

    context 'when Gitaly times out' do
      it 'caches the timeout and fails subsequent calls without reaching Gitaly', :aggregate_failures do
        expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id)
          .once.and_raise(GRPC::DeadlineExceeded)

        expect { build_stats }.to raise_error(Gitlab::Git::CommandTimedOut)
        expect { build_stats }.to raise_error(
          Gitlab::Git::CommandTimedOut,
          "commit stats for #{commit.id} timed out within the last #{described_class::TIMED_OUT_EXPIRY.inspect}"
        )
        expect(Rails.cache.exist?(timed_out_cache_key)).to be(true)
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'retries after the original timeout expires even if the cached timeout was read', :aggregate_failures do
        expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id)
          .once.and_raise(GRPC::DeadlineExceeded)

        expect { build_stats }.to raise_error(Gitlab::Git::CommandTimedOut)
        expires_at = described_class::TIMED_OUT_EXPIRY.from_now + 1.second

        travel_to(5.minutes.from_now)
        expect { build_stats }.to raise_error(Gitlab::Git::CommandTimedOut)

        travel_to(expires_at)
        expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id).once.and_call_original

        expect(build_stats).to have_attributes(additions: 5, deletions: 0, files: 1, total: 5)
        expect(Rails.cache.read(cache_key)).to eq([5, 0, 1])
      end

      context 'when commit_stats_failure_handling is disabled' do
        before do
          stub_feature_flags(commit_stats_failure_handling: false)
        end

        it 'retries Gitaly without caching the timeout', :aggregate_failures do
          expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id)
            .twice.and_raise(GRPC::DeadlineExceeded)

          2.times do
            expect { build_stats }.to raise_error(Gitlab::Git::CommandTimedOut)
          end

          expect(Rails.cache.exist?(timed_out_cache_key)).to be(false)
        end

        it 'returns stats from Gitaly despite an existing timeout marker', :aggregate_failures do
          Rails.cache.write(timed_out_cache_key, true, expires_in: described_class::TIMED_OUT_EXPIRY)
          expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id).once.and_call_original

          expect(build_stats).to have_attributes(additions: 5, deletions: 0, files: 1, total: 5)
        end
      end
    end

    context 'when Gitaly raises another command error' do
      it 'does not cache the failure', :aggregate_failures do
        expect(repository.gitaly_commit_client).to receive(:commit_stats).with(commit.id)
          .twice.and_raise(GRPC::Internal)

        2.times do
          expect { build_stats }.to raise_error(Gitlab::Git::CommandError)
        end

        expect(Rails.cache.read(cache_key)).to be_nil
        expect(Rails.cache.exist?(timed_out_cache_key)).to be(false)
      end
    end
  end
end
