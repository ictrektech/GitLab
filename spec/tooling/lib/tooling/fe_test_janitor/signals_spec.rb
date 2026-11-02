# frozen_string_literal: true

require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/signals'

RSpec.describe Tooling::FeTestJanitor::Signals, feature_category: :tooling do
  describe 'KEEP patterns' do
    subject(:keep_patterns) { described_class::KEEP }

    it 'does not match sign_in, since MSW fixtures provide the signed-in user' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('sign_in(user)') }).to be false
    end

    it 'does not match FactoryBot calls, since MSW fixtures provide the records' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('create_list(:milestone, 3, project: project)') }).to be false
    end

    it 'matches perform_enqueued_jobs' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('perform_enqueued_jobs { do_something }') }).to be true
    end

    it 'matches stub_request' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('stub_request(:get, url)') }).to be true
    end

    it 'matches drag_to' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('element.drag_to(target)') }).to be true
    end

    it 'matches attach_file' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('attach_file("file", path)') }).to be true
    end

    it 'matches be_axe_clean' do
      expect(keep_patterns.any? { |s| s[:pattern].match?('expect(page).to be_axe_clean') }).to be true
    end
  end

  describe 'REFRAME patterns' do
    subject(:reframe_patterns) { described_class::REFRAME }

    it 'matches reload' do
      expect(reframe_patterns.any? { |s| s[:pattern].match?('expect(work_item.reload.title).to eq(title)') }).to be true
    end

    it 'matches change blocks' do
      expect(reframe_patterns.any? { |s| s[:pattern].match?('.to change { Note.count }.by(1)') }).to be true
    end

    it 'matches model queries' do
      expect(reframe_patterns.any? { |s| s[:pattern].match?('WorkItems::Type.last.name') }).to be true
    end

    it 'does not match UI assertions' do
      expect(reframe_patterns.any? { |s| s[:pattern].match?("have_content('Last updated')") }).to be false
    end
  end

  describe 'MIGRATE patterns' do
    subject(:migrate_patterns) { described_class::MIGRATE }

    it 'matches quarantine tag' do
      expect(migrate_patterns.any? { |s| s[:pattern].match?("quarantine: 'https://example.com'") }).to be true
    end

    it 'matches graphql_mutation' do
      expect(migrate_patterns.any? { |s| s[:pattern].match?('graphql_mutation(:update_work_item, input)') }).to be true
    end

    it 'matches have_css with data-testid' do
      assertion = "have_css('[data-testid=\"work-item-title\"]')"

      expect(migrate_patterns.any? { |s| s[:pattern].match?(assertion) }).to be true
    end

    it 'matches have_selector' do
      expect(migrate_patterns.any? { |s| s[:pattern].match?("have_selector('[data-testid=\"foo\"]')") }).to be true
    end
  end
end
