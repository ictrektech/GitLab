# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Projects::WritePolicy, feature_category: :importers do
  subject(:read_only) { described_class.read_only?(project) }

  let_it_be_with_reload(:project) { create(:project) }

  before do
    stub_feature_flags(github_continuous_import_enforcement: true)
  end

  context 'when the project is synced from GitHub' do
    before do
      project.update!(import_type: 'github')
    end

    context 'and the import_sync repository is read-only' do
      before do
        create(:import_sync_repository, project: project, authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset
      end

      it { is_expected.to be(true) }
    end

    context 'and the import_sync repository is writable' do
      before do
        create(:import_sync_repository, project: project, authority_state: :gitlab_canonical)
        project.association(:import_sync_repository).reset
      end

      it { is_expected.to be(false) }
    end

    context 'without an import_sync repository' do
      it { is_expected.to be(false) }
    end
  end

  context 'without a project' do
    let(:project) { nil }

    it { is_expected.to be(false) }
  end

  context 'with a non-GitHub project' do
    it 'does not load the import_sync association' do
      expect(project).not_to receive(:import_sync_repository)

      expect(read_only).to be(false)
    end
  end

  context 'with an unsaved project' do
    let(:import_sync_repository) { build(:import_sync_repository, authority_state: :provider_canonical) }
    let(:project) { import_sync_repository.project.tap { |p| p.import_type = 'github' } }

    it { is_expected.to be(true) }
  end

  context 'when import metadata no longer identifies GitHub' do
    before do
      project.update!(import_type: 'jira')
      create(:import_sync_repository, project: project, authority_state: :provider_canonical)
      project.association(:import_sync_repository).reset
    end

    it { is_expected.to be(false) }
  end

  context 'when the github_continuous_import_enforcement feature flag is disabled' do
    before do
      project.update!(import_type: 'github')
      create(:import_sync_repository, project: project, authority_state: :provider_canonical)
      project.association(:import_sync_repository).reset

      stub_feature_flags(github_continuous_import_enforcement: false)
    end

    it { is_expected.to be(false) }
  end

  describe '.repository_mirroring_blocked?' do
    subject(:blocked) { described_class.repository_mirroring_blocked?(project) }

    context 'with durable provider binding' do
      before do
        create(:import_sync_repository, project: project, authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset
      end

      it { is_expected.to be(true) }

      context 'when import metadata no longer identifies GitHub' do
        before do
          project.update!(import_type: 'jira')
        end

        it { is_expected.to be(true) }
      end
    end

    context 'when provider binding is retired' do
      before do
        create(:import_sync_repository, project: project, authority_state: :gitlab_canonical)
        project.association(:import_sync_repository).reset
      end

      it { is_expected.to be(false) }
    end

    context 'without a project' do
      let(:project) { nil }

      it { is_expected.to be(false) }
    end

    context 'without an import_sync repository' do
      it { is_expected.to be(false) }
    end

    context 'when the github_continuous_import_enforcement feature flag is disabled' do
      before do
        create(:import_sync_repository, project: project, authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset

        stub_feature_flags(github_continuous_import_enforcement: false)
      end

      it { is_expected.to be(false) }
    end
  end
end
