# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::Finding, feature_category: :dap_code_review do
  subject(:finding) { build(:duo_code_review_finding) }

  describe 'associations' do
    it { is_expected.to belong_to(:note).required.inverse_of(:duo_code_review_finding) }
    it { is_expected.to belong_to(:project).required }
    it { is_expected.to belong_to(:merge_request).required }
    it { is_expected.to belong_to(:workflow).class_name('Ai::DuoWorkflows::Workflow').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:severity) }
    it { is_expected.to validate_presence_of(:depth) }
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_length_of(:category).is_at_most(described_class::CATEGORY_MAX_LENGTH) }
    it { is_expected.to validate_numericality_of(:confidence).only_integer.is_in(0..10).allow_nil }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:severity).with_values(critical: 1, major: 2, minor: 3) }
    it { is_expected.to define_enum_for(:depth).with_values(standard: 1, deep: 2).with_prefix }
  end

  describe 'sharding key' do
    let_it_be(:merge_request) { create(:merge_request) }

    subject { build(:duo_code_review_finding, merge_request: merge_request, project: nil) }

    it { is_expected.to populate_sharding_key(:project_id).with(merge_request.project_id) }
  end

  context 'with loose foreign key on duo_code_review_findings.note_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:diff_note_on_merge_request) }
      let_it_be(:model) { create(:duo_code_review_finding, note: parent) }
    end
  end
end
