# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::Pins::MergeDefaultsService, feature_category: :navigation do
  let_it_be_with_reload(:user) { create(:user) }

  let(:defaults_by_panel) { { 'group' => %w[group_overview members], 'project' => %w[project_overview pipelines] } }

  subject(:execute) { described_class.new(user, defaults_by_panel: defaults_by_panel).execute }

  def merge_recorded?
    Users::Callout.exists?(user: user, feature_name: described_class::CALLOUT_FEATURE_NAME)
  end

  describe '.merge' do
    it 'appends missing defaults to saved panels, fills empty panels, and leaves unsaved panels unset' do
      saved_pins = { 'project' => %w[pipelines], 'group' => [] }

      expect(described_class.merge(saved_pins, defaults_by_panel)).to eq(
        'project' => %w[pipelines project_overview],
        'group' => %w[group_overview members]
      )
      expect(described_class.merge({ 'project' => %w[pipelines] }, defaults_by_panel)).to eq(
        'project' => %w[pipelines project_overview]
      )
    end

    it 'does not modify the saved pins' do
      saved_pins = { 'project' => %w[pipelines] }

      described_class.merge(saved_pins, defaults_by_panel)

      expect(saved_pins).to eq('project' => %w[pipelines])
    end
  end

  context 'when the user has customised pins' do
    before do
      user.update!(pinned_nav_items: { 'project' => %w[pipelines branches], 'group' => [] })
    end

    it 'appends the missing defaults after the saved pins and records the merge', :aggregate_failures do
      expect(execute).to be_success
      expect(user.reload.pinned_nav_items).to eq(
        'project' => %w[pipelines branches project_overview],
        'group' => %w[group_overview members]
      )
      expect(merge_recorded?).to be(true)
    end

    it 'does not merge again once recorded' do
      execute
      user.update!(pinned_nav_items: { 'project' => %w[branches] })

      # A fresh record, as on the next request: User memoizes callouts across reload.
      described_class.new(User.find(user.id), defaults_by_panel: defaults_by_panel).execute

      expect(user.reload.pinned_nav_items).to eq('project' => %w[branches])
    end
  end

  context 'when another request already claimed the merge' do
    before do
      user.update!(pinned_nav_items: { 'project' => %w[branches] })
      # Loaded before the other request's claim, as a concurrent request would be.
      user.callouts.load
      create(:callout, user: user, feature_name: described_class::CALLOUT_FEATURE_NAME)
    end

    it 'does not merge or raise', :aggregate_failures do
      expect(execute).to be_success
      expect(user.reload.pinned_nav_items).to eq('project' => %w[branches])
    end
  end

  context 'when a panel has no saved pins' do
    before do
      user.update!(pinned_nav_items: { 'project' => %w[branches] })
    end

    it 'leaves that panel falling back to the defaults' do
      execute

      expect(user.reload.pinned_nav_items).to eq('project' => %w[branches project_overview pipelines])
    end
  end

  context 'when the merged pins are invalid' do
    let(:defaults_by_panel) { { 'project' => [1] } }

    before do
      user.update!(pinned_nav_items: { 'project' => %w[branches] })
    end

    it 'returns an error, keeps the saved pins, and still records the attempt so it is not retried',
      :aggregate_failures do
      expect(execute).to be_error
      expect(execute.reason).to eq(:invalid_pins)
      expect(execute.message).to match(/\AFailed to merge default pins: \S/)
      expect(user.pinned_nav_items).to eq('project' => %w[branches])
      expect(user.reload.pinned_nav_items).to eq('project' => %w[branches])
      expect(merge_recorded?).to be(true)
    end
  end

  context 'when the user has no saved pins' do
    it 'records the merge without writing the preference', :aggregate_failures do
      expect(user.user_preference).not_to receive(:update)

      expect(execute).to be_success
      expect(merge_recorded?).to be(true)
    end
  end

  context 'when an unrelated user attribute is invalid' do
    before do
      user.update!(pinned_nav_items: { 'project' => %w[branches] })
      user.update_column(:name, 'a' * 256)
    end

    it 'still merges, because only the preference is saved' do
      expect(execute).to be_success
      expect(user.reload.pinned_nav_items['project']).to eq(%w[branches project_overview pipelines])
    end
  end

  context 'when the database is read-only' do
    before do
      user.update!(pinned_nav_items: { 'project' => %w[branches] })
      allow(Gitlab::Database).to receive(:read_only?).and_return(true)
    end

    it 'does nothing', :aggregate_failures do
      expect(execute).to be_success
      expect(user.reload.pinned_nav_items).to eq('project' => %w[branches])
      expect(merge_recorded?).to be(false)
    end
  end
end
