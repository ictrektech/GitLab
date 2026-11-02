# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Skills::PublishWorker, feature_category: :ai_catalog_creation do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :small_repo, group: group) }

  let(:oldrev) { 'oldrev' }
  let(:newrev) { 'newrev' }
  let(:ref) { "refs/heads/#{project.default_branch}" }

  subject(:perform) { described_class.new.perform(project.id, oldrev, newrev, ref) }

  before do
    stub_licensed_features(ai_catalog: true)
  end

  def stub_push(modified_paths:, branch_updated: true)
    push = instance_double(::Gitlab::Git::Push, branch_updated?: branch_updated)
    allow(push).to receive(:modified_paths).and_return(modified_paths)
    allow(::Gitlab::Git::Push).to receive(:new).with(project, oldrev, newrev, ref).and_return(push)
  end

  def expect_publish(result: ServiceResponse.success(payload: {}))
    expect(::Ai::Catalog::Skills::PublishService).to receive(:new)
      .with(project: project).once
      .and_return(instance_double(::Ai::Catalog::Skills::PublishService, execute: result))
  end

  describe '#perform' do
    it 'publishes when a SKILL.md changed' do
      stub_push(modified_paths: ['README.md', 'skills/cosign-blob/SKILL.md'])
      expect_publish

      perform
    end

    it 'publishes when a SKILL.md was deleted, so the item is reconciled away' do
      stub_push(modified_paths: ['skills/cosign-blob/SKILL.md'])
      expect_publish

      perform
    end

    context 'when no skill file changed' do
      where(:modified_paths) do
        [
          [['README.md']],
          [['skills/cosign-blob/references/flags.md']],
          [['skills/SKILL.md']],
          [['skills/a/b/SKILL.md']],
          [['docs/skills/cosign-blob/SKILL.md']],
          [[]]
        ]
      end

      with_them do
        it 'does nothing' do
          stub_push(modified_paths: modified_paths)
          expect(::Ai::Catalog::Skills::PublishService).not_to receive(:new)

          perform
        end
      end
    end

    it 'does nothing when the branch was added or removed, where paths cannot be computed' do
      stub_push(modified_paths: [], branch_updated: false)
      expect(::Ai::Catalog::Skills::PublishService).not_to receive(:new)

      perform
    end

    it 'does nothing when the project no longer exists' do
      expect(::Ai::Catalog::Skills::PublishService).not_to receive(:new)

      described_class.new.perform(non_existing_record_id, oldrev, newrev, ref)
    end

    it 'does nothing when the project is not licensed for the AI Catalog' do
      stub_licensed_features(ai_catalog: false)
      expect(::Ai::Catalog::Skills::PublishService).not_to receive(:new)

      perform
    end

    it 'does nothing when Duo features are disabled for the project' do
      project.project_setting.update!(duo_features_enabled: false)
      expect(::Ai::Catalog::Skills::PublishService).not_to receive(:new)

      perform
    end

    describe 'error handling' do
      before do
        stub_push(modified_paths: ['skills/cosign-blob/SKILL.md'])
      end

      it 'logs a failed scan' do
        expect_publish(result: ServiceResponse.error(message: 'Could not read', reason: :scan_failed))

        expect(::Gitlab::AppJsonLogger).to receive(:warn).with(
          hash_including(
            'message' => 'Failed to publish skills after a push',
            'gl_project_id' => project.id,
            'reason' => :scan_failed
          )
        )

        perform
      end

      it 'raises so Sidekiq retries when the lease is already taken', :aggregate_failures do
        expect_publish(result: ServiceResponse.error(message: 'Another publish', reason: :lease_taken))

        expect(::Gitlab::AppJsonLogger).not_to receive(:warn)
        expect { perform }.to raise_error(described_class::LeaseTakenError, 'Another publish')
      end
    end
  end

  it 'backs off a fixed interval for lease contention and defaults for anything else',
    :aggregate_failures do
    retry_in = described_class.sidekiq_retry_in_block

    expect(retry_in.call(1, described_class::LeaseTakenError.new, {})).to eq(30)
    expect(retry_in.call(1, StandardError.new, {})).to be_nil
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [project.id, oldrev, newrev, ref] }

    before do
      stub_push(modified_paths: ['skills/cosign-blob/SKILL.md'])
    end

    it 'publishes nothing' do
      expect { perform_idempotent_work }.not_to change { ::Ai::Catalog::Item.count }
    end
  end
end
