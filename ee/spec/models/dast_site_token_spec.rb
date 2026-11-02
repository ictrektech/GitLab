# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DastSiteToken do
  subject { create(:dast_site_token) }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
  end

  describe 'validations' do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:project_id) }
    it { is_expected.to validate_length_of(:token).is_at_most(255) }
    it { is_expected.to validate_length_of(:url).is_at_most(255) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_uniqueness_of(:token).scoped_to(:project_id) }
    it { is_expected.to validate_uniqueness_of(:url).scoped_to(:project_id) }

    it_behaves_like 'dast url addressable'

    context 'when token is reused' do
      let_it_be(:existing_token) { create(:dast_site_token) }

      it 'allows the same token in a different project' do
        other_token = build(:dast_site_token, token: existing_token.token, project: create(:project))

        expect(other_token).to be_valid
        expect { other_token.save! }.to change { described_class.count }.by(1)
      end

      it 'does not allow the same token in the same project' do
        duplicate_token = build(:dast_site_token, token: existing_token.token, project: existing_token.project)

        expect(duplicate_token).not_to be_valid
        expect(duplicate_token.errors[:token]).to include('has already been taken')
      end

      it 'enforces uniqueness of token and project_id in the database' do
        other_token = create(:dast_site_token, project: existing_token.project)

        expect { other_token.update_column(:token, existing_token.token) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe '#dast_site' do
    context 'when dast_site exists' do
      it 'finds the associated dast_site' do
        dast_site = create(:dast_site, project_id: subject.project_id, url: subject.url)

        expect(subject.dast_site).to eq(dast_site)
      end
    end

    context 'when dast_site does not exist' do
      it 'returns nil' do
        expect(subject.dast_site).to be_nil
      end
    end
  end

  context 'with loose foreign key on dast_site_tokens.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) { create(:dast_site_token, project: parent) }
    end
  end
end
