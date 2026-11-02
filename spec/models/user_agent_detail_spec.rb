# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UserAgentDetail, feature_category: :insider_threat do
  it { is_expected.to belong_to(:organization).required }

  describe 'scopes' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:issue) { create(:issue) }
    let_it_be(:other_issue) { create(:issue) }
    let_it_be(:snippet) { create(:personal_snippet) }

    let_it_be(:issue_detail) { create(:user_agent_detail, subject: issue, organization: organization) }
    let_it_be(:snippet_detail) { create(:user_agent_detail, subject: snippet, organization: organization) }
    let_it_be(:other_issue_detail) do
      create(:user_agent_detail, subject: other_issue, organization: other_organization)
    end

    describe '.in_organization' do
      it 'returns details belonging to the organization' do
        expect(described_class.in_organization(organization)).to contain_exactly(issue_detail, snippet_detail)
      end
    end

    describe '.for_subjects' do
      it 'returns details matching the subject type and ids' do
        expect(described_class.for_subjects('Issue', [issue.id])).to contain_exactly(issue_detail)
        expect(described_class.for_subjects('Snippet', [snippet.id])).to contain_exactly(snippet_detail)
      end
    end
  end

  describe '.submittable?' do
    it 'is submittable when not already submitted' do
      detail = build(:user_agent_detail)

      expect(detail.submittable?).to be_truthy
    end

    it 'is not submittable when already submitted' do
      detail = build(:user_agent_detail, submitted: true)

      expect(detail.submittable?).to be_falsey
    end
  end

  describe '.valid?' do
    let(:issue) { create(:issue) }

    it 'is valid with a subject' do
      detail = build(:user_agent_detail, subject: issue)

      expect(detail).to be_valid
    end

    it 'is invalid without a subject' do
      detail = build(:user_agent_detail, subject: nil)

      expect(detail).not_to be_valid
    end
  end
end
